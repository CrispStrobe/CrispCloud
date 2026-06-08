<?php

declare(strict_types=1);

namespace OCA\CrispCloudDelta\Service;

use OCP\Files\IRootFolder;
use OCP\Files\NotFoundException;
use OCP\IConfig;
use Psr\Log\LoggerInterface;

/**
 * Computes, caches, and serves block-level file indexes.
 *
 * Block map format (JSON):
 * {
 *   "filePath": "/path/to/file",
 *   "totalSize": 104857600,
 *   "blockSize": 4194304,
 *   "blockCount": 25,
 *   "signatures": [
 *     {"blockIndex": 0, "offset": 0, "size": 4194304, "weakHash": 12345, "strongHash": "abcdef..."},
 *     ...
 *   ],
 *   "createdAt": "2026-06-08T12:00:00Z",
 *   "etag": "abc123"
 * }
 */
class BlockMapService {
    private const BLOCK_SIZE = 4 * 1024 * 1024; // 4 MB
    private const ADLER_MOD = 65521;
    private const CACHE_FOLDER = '.crispcloud_delta';

    private IRootFolder $rootFolder;
    private IConfig $config;
    private LoggerInterface $logger;

    public function __construct(
        IRootFolder $rootFolder,
        IConfig $config,
        LoggerInterface $logger
    ) {
        $this->rootFolder = $rootFolder;
        $this->config = $config;
        $this->logger = $logger;
    }

    /**
     * Get or compute the block map for a file.
     *
     * Returns cached map if the file's ETag hasn't changed.
     * Recomputes and caches if stale or missing.
     */
    public function getBlockMap(string $userId, string $path): ?array {
        $userFolder = $this->rootFolder->getUserFolder($userId);

        try {
            $file = $userFolder->get($path);
        } catch (NotFoundException $e) {
            return null;
        }

        if ($file->getType() !== \OCP\Files\FileInfo::TYPE_FILE) {
            return null;
        }

        $etag = $file->getEtag();
        $fileSize = $file->getSize();

        // Check cache
        $cached = $this->loadCachedBlockMap($userId, $path);
        if ($cached !== null && isset($cached['etag']) && $cached['etag'] === $etag) {
            return $cached;
        }

        // Compute fresh block map
        $this->logger->info("Computing block map for {path} ({size} bytes)", [
            'path' => $path,
            'size' => $fileSize,
        ]);

        $blockMap = $this->computeBlockMap($file, $path);
        $blockMap['etag'] = $etag;

        // Cache it
        $this->saveCachedBlockMap($userId, $path, $blockMap);

        return $blockMap;
    }

    /**
     * Compute the block map for a Nextcloud file node.
     */
    private function computeBlockMap(\OCP\Files\File $file, string $path): array {
        $size = $file->getSize();
        $blockSize = self::BLOCK_SIZE;
        $blockCount = $size === 0 ? 0 : (int)ceil($size / $blockSize);
        $signatures = [];

        $handle = $file->fopen('rb');
        if ($handle === false) {
            throw new \RuntimeException("Cannot open file: $path");
        }

        try {
            for ($i = 0; $i < $blockCount; $i++) {
                $offset = $i * $blockSize;
                $remaining = min($blockSize, $size - $offset);
                $data = '';
                // fread may return short reads — loop until we have the full block
                while (strlen($data) < $remaining) {
                    $chunk = fread($handle, $remaining - strlen($data));
                    if ($chunk === false || $chunk === '') {
                        break;
                    }
                    $data .= $chunk;
                }
                if (strlen($data) === 0) {
                    break;
                }
                $actualSize = strlen($data);

                $signatures[] = [
                    'blockIndex' => $i,
                    'offset' => $offset,
                    'size' => $actualSize,
                    'weakHash' => $this->adler32($data),
                    'strongHash' => hash('sha256', $data),
                ];
            }
        } finally {
            fclose($handle);
        }

        return [
            'filePath' => $path,
            'totalSize' => $size,
            'blockSize' => $blockSize,
            'blockCount' => $blockCount,
            'signatures' => $signatures,
            'createdAt' => (new \DateTimeImmutable())->format(\DateTimeInterface::ATOM),
        ];
    }

    /**
     * Adler-32 checksum (RFC 1950) — must match the Dart implementation.
     */
    private function adler32(string $data): int {
        $a = 1;
        $b = 0;
        $len = strlen($data);

        for ($i = 0; $i < $len; $i++) {
            $a = ($a + ord($data[$i])) % self::ADLER_MOD;
            $b = ($b + $a) % self::ADLER_MOD;
        }

        return ($b << 16) | $a;
    }

    /**
     * Write a block of data at a specific offset in a file.
     */
    public function writeBlock(string $userId, string $path, int $offset, string $data): void {
        $userFolder = $this->rootFolder->getUserFolder($userId);
        $file = $userFolder->get($path);

        if ($file->getType() !== \OCP\Files\FileInfo::TYPE_FILE) {
            throw new \RuntimeException("Not a file: $path");
        }

        // Read current content, patch the block, write back
        $handle = $file->fopen('cb+'); // open for read/write, create if needed
        if ($handle === false) {
            throw new \RuntimeException("Cannot open file for writing: $path");
        }

        try {
            fseek($handle, $offset, SEEK_SET);
            fwrite($handle, $data);
            fflush($handle);
        } finally {
            fclose($handle);
        }

        $this->logger->debug("Wrote block at offset {offset} ({size} bytes) to {path}", [
            'offset' => $offset,
            'size' => strlen($data),
            'path' => $path,
        ]);
    }

    /**
     * Finalize a file after block writes — touch mtime and invalidate cache.
     */
    public function finalizeFile(string $userId, string $path): void {
        $userFolder = $this->rootFolder->getUserFolder($userId);
        $file = $userFolder->get($path);

        // Touch triggers Nextcloud to update ETag and mtime
        $file->touch();

        // Recompute and cache the block map with the new ETag
        $blockMap = $this->computeBlockMap($file, $path);
        $blockMap['etag'] = $file->getEtag();
        $this->saveCachedBlockMap($userId, $path, $blockMap);

        $this->logger->info("Finalized delta sync for {path}", ['path' => $path]);
    }

    // -------------------------------------------------------------------------
    // Cache helpers
    // -------------------------------------------------------------------------

    private function getCachePath(string $userId, string $path): string {
        $hash = hash('sha256', $path);
        return self::CACHE_FOLDER . '/' . $hash . '.json';
    }

    private function loadCachedBlockMap(string $userId, string $path): ?array {
        $userFolder = $this->rootFolder->getUserFolder($userId);
        $cachePath = $this->getCachePath($userId, $path);

        try {
            $cacheFile = $userFolder->get($cachePath);
            $json = $cacheFile->getContent();
            return json_decode($json, true);
        } catch (NotFoundException $e) {
            return null;
        } catch (\Throwable $e) {
            $this->logger->warning("Failed to load cached block map: {error}", [
                'error' => $e->getMessage(),
            ]);
            return null;
        }
    }

    private function saveCachedBlockMap(string $userId, string $path, array $blockMap): void {
        $userFolder = $this->rootFolder->getUserFolder($userId);
        $cachePath = $this->getCachePath($userId, $path);

        try {
            // Ensure cache folder exists
            try {
                $userFolder->get(self::CACHE_FOLDER);
            } catch (NotFoundException $e) {
                $userFolder->newFolder(self::CACHE_FOLDER);
            }

            $json = json_encode($blockMap, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);

            try {
                $cacheFile = $userFolder->get($cachePath);
                $cacheFile->putContent($json);
            } catch (NotFoundException $e) {
                $userFolder->newFile($cachePath, $json);
            }
        } catch (\Throwable $e) {
            $this->logger->warning("Failed to save cached block map: {error}", [
                'error' => $e->getMessage(),
            ]);
        }
    }
}
