<?php

declare(strict_types=1);

namespace OCA\CrispCloudDelta\Controller;

use OCA\CrispCloudDelta\Service\BlockMapService;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http;
use OCP\AppFramework\Http\JSONResponse;
use OCP\IRequest;

class DeltaController extends Controller {
    private BlockMapService $blockMapService;
    private string $userId;

    public function __construct(
        string $appName,
        IRequest $request,
        BlockMapService $blockMapService,
        string $userId
    ) {
        parent::__construct($appName, $request);
        $this->blockMapService = $blockMapService;
        $this->userId = $userId;
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     *
     * GET /api/blockmap/{path}
     *
     * Returns the block map (Adler-32 + SHA-256 per 4 MB block) for a file.
     * Cached server-side; recomputed when ETag changes.
     */
    public function getBlockMap(string $path): JSONResponse {
        $blockMap = $this->blockMapService->getBlockMap($this->userId, '/' . $path);

        if ($blockMap === null) {
            return new JSONResponse(
                ['error' => 'File not found or not a regular file'],
                Http::STATUS_NOT_FOUND
            );
        }

        return new JSONResponse($blockMap);
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     *
     * PUT /api/blocks/{path}?offset=N&size=M
     *
     * Write a single block at the given offset. The request body is the raw
     * block data. Used by CrispCloud's DeltaSyncService to upload only the
     * changed blocks of a large file.
     */
    public function putBlock(string $path): JSONResponse {
        $offset = (int)$this->request->getParam('offset', '0');
        $size = (int)$this->request->getParam('size', '0');

        // Read raw body
        $data = file_get_contents('php://input');
        if ($data === false || strlen($data) === 0) {
            return new JSONResponse(
                ['error' => 'Empty request body'],
                Http::STATUS_BAD_REQUEST
            );
        }

        if ($size > 0 && strlen($data) !== $size) {
            return new JSONResponse(
                ['error' => "Size mismatch: expected $size, got " . strlen($data)],
                Http::STATUS_BAD_REQUEST
            );
        }

        try {
            $this->blockMapService->writeBlock($this->userId, '/' . $path, $offset, $data);
        } catch (\Throwable $e) {
            return new JSONResponse(
                ['error' => $e->getMessage()],
                Http::STATUS_INTERNAL_SERVER_ERROR
            );
        }

        return new JSONResponse(['status' => 'ok', 'offset' => $offset, 'size' => strlen($data)]);
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     *
     * POST /api/finalize/{path}
     *
     * Called after all block writes are complete. Updates the file's mtime,
     * recomputes the block map, and refreshes the ETag.
     */
    public function finalize(string $path): JSONResponse {
        try {
            $this->blockMapService->finalizeFile($this->userId, '/' . $path);
        } catch (\Throwable $e) {
            return new JSONResponse(
                ['error' => $e->getMessage()],
                Http::STATUS_INTERNAL_SERVER_ERROR
            );
        }

        return new JSONResponse(['status' => 'finalized']);
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     * @PublicPage
     *
     * GET /api/status
     *
     * Health check — confirms the app is installed and the API is reachable.
     */
    public function status(): JSONResponse {
        return new JSONResponse([
            'app' => 'crispcloud_delta',
            'version' => '0.1.0',
            'status' => 'ok',
            'blockSize' => 4 * 1024 * 1024,
            'algorithm' => 'adler32+sha256',
        ]);
    }
}
