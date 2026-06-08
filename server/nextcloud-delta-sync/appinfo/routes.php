<?php

declare(strict_types=1);

return [
    'routes' => [
        // Block map retrieval
        ['name' => 'delta#getBlockMap', 'url' => '/api/blockmap/{path}', 'verb' => 'GET',
         'requirements' => ['path' => '.+']],

        // Block-level write (partial file update) — uses POST because Apache
        // blocks PUT on non-WebDAV URLs by default
        ['name' => 'delta#putBlock', 'url' => '/api/blocks/{path}', 'verb' => 'POST',
         'requirements' => ['path' => '.+']],

        // Finalize after block writes
        ['name' => 'delta#finalize', 'url' => '/api/finalize/{path}', 'verb' => 'POST',
         'requirements' => ['path' => '.+']],

        // Status check
        ['name' => 'delta#status', 'url' => '/api/status', 'verb' => 'GET'],
    ],
];
