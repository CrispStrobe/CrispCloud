// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

// Native header derivations run in a cancellable, serialized isolate queue.
// Browser derivations use the synchronous service's explicit resource policy.
export 'veracrypt_header_worker_stub.dart'
    if (dart.library.io) 'veracrypt_header_worker_io.dart'
    show unlockVeraCryptHeaderAsync;
