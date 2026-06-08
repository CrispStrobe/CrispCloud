# CrispCloud Delta Sync — Nextcloud Server App

Companion server-side app for [CrispCloud](https://github.com/CrispStrobe/CrispCloud) that enables **block-level delta sync** for large files.

## What it does

Instead of re-uploading an entire 500 MB VeraCrypt container when only 8 MB of blocks changed, this app:

1. **Maintains block-level indexes** — Adler-32 weak hash + SHA-256 strong hash per 4 MB block, cached per file
2. **Serves block maps via REST API** — CrispCloud client compares local vs remote block maps to find diffs
3. **Accepts partial block writes** — only changed blocks are uploaded, written at their exact file offset
4. **Auto-recomputes on change** — if the file's ETag changes (edited by another client), the block map is recomputed

## Installation

```bash
# Copy to Nextcloud apps directory
cp -r nextcloud-delta-sync /path/to/nextcloud/apps/crispcloud_delta

# Enable the app
cd /path/to/nextcloud
php occ app:enable crispcloud_delta
```

## API Endpoints

All endpoints require authentication (same credentials as WebDAV).

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/apps/crispcloud_delta/api/blockmap/{path}` | Get block map (auto-computed, cached by ETag) |
| `PUT` | `/apps/crispcloud_delta/api/blocks/{path}?offset=N&size=M` | Write a single block at offset |
| `POST` | `/apps/crispcloud_delta/api/finalize/{path}` | Finalize after block writes (touch mtime, recompute block map) |
| `GET` | `/apps/crispcloud_delta/api/status` | Health check |

## Block Map Format

```json
{
  "filePath": "/Documents/vault.vc",
  "totalSize": 524288000,
  "blockSize": 4194304,
  "blockCount": 125,
  "signatures": [
    {
      "blockIndex": 0,
      "offset": 0,
      "size": 4194304,
      "weakHash": 1234567890,
      "strongHash": "a1b2c3d4e5f6..."
    }
  ],
  "createdAt": "2026-06-08T12:00:00+00:00",
  "etag": "abc123def456"
}
```

The format is identical to CrispCloud's `DeltaSyncService.BlockMap` JSON serialization, so the client can deserialize it directly.

## How it works with CrispCloud

1. CrispCloud detects the server app via `GET /api/status`
2. On sync, CrispCloud calls `GET /api/blockmap/{path}` to get the remote block map
3. CrispCloud computes the local block map (Adler-32 + SHA-256 per 4 MB block)
4. Comparison yields a list of changed block indices
5. Only changed blocks are uploaded via `PUT /api/blocks/{path}?offset=N`
6. `POST /api/finalize/{path}` updates the file and refreshes the cached block map

## Without this app

CrispCloud still works — it falls back to:
- **ETag-gated caching**: stores the remote block map locally after each sync
- **Full file re-upload via chunked upload v2** when blocks change (no partial update)
- Block map comparison still saves computation on subsequent syncs

## Compatibility

| Platform | Supported | Notes |
|----------|-----------|-------|
| **Nextcloud 25–31** | Yes | Primary target |
| **ownCloud 10.11+** | Yes | Shared OCP AppFramework + Files API from pre-fork era |
| **ownCloud Infinite Scale (oCIS)** | No | Go-based, no PHP apps — use Graph/delta API instead (same as OneDrive) |

### Requirements

- PHP 8.0+
- The app uses only stable OCP APIs that exist in both Nextcloud and ownCloud 10:
  - `OCP\Files\IRootFolder`, `OCP\Files\File`, `OCP\Files\FileInfo`
  - `OCP\AppFramework\Controller`, `OCP\AppFramework\Http\JSONResponse`
  - `OCP\IConfig`, `OCP\IRequest`

## License

AGPL-3.0 (same as CrispCloud and Nextcloud)
