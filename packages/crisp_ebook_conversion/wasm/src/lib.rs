//! Offline, metadata-only byte ABI for the bundled browser worker.
//! No filesystem, clock, random data, native threads or browser imports are used
//! by the called metadata path. A worker owns every allocation for one request.
use kindling::mobi_rewrite::{ExthChange, MetadataUpdates, RewriteError};
use serde::Deserialize;
use serde_json::{Value, json};

const MAX_INPUT: usize = 64 * 1024 * 1024;
const MAX_OUTPUT: usize = 128 * 1024 * 1024;
const MAX_JSON: usize = 131_072;

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct Metadata {
    title: Option<String>,
    authors: Option<Vec<String>>,
    publisher: Option<String>,
    description: Option<String>,
    language: Option<String>,
    isbn: Option<String>,
    asin: Option<String>,
    publication_date: Option<String>,
    subjects: Option<Vec<String>>,
    identifier: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    format: String,
    #[serde(default)]
    metadata: Metadata,
    input_limit: usize,
    output_limit: usize,
}

pub struct Reply {
    metadata: Vec<u8>,
    data: Vec<u8>,
}

impl Reply {
    fn error(code: &str, message: &str) -> Self {
        Self {
            metadata: json!({"ok": false, "code": code, "message": message})
                .to_string()
                .into_bytes(),
            data: Vec::new(),
        }
    }
}

fn rewrite(input: &[u8], request: &[u8]) -> Reply {
    if request.len() > MAX_JSON {
        return Reply::error("limitExceeded", "Metadata is too large.");
    }
    let request: Request = match serde_json::from_slice(request) {
        Ok(value) => value,
        Err(_) => return Reply::error("invalidInput", "Invalid metadata request."),
    };
    if !matches!(request.format.as_str(), "azw3" | "mobi") {
        return Reply::error("unsupportedFormat", "Unsupported Kindle container format.");
    }
    if request.input_limit == 0
        || request.input_limit > MAX_INPUT
        || request.output_limit == 0
        || request.output_limit > MAX_OUTPUT
        || input.is_empty()
        || input.len() > request.input_limit
    {
        return Reply::error(
            "limitExceeded",
            "Ebook size exceeds the browser metadata limit.",
        );
    }
    let metadata = request.metadata;
    let updates = MetadataUpdates {
        title: metadata.title,
        authors: metadata.authors,
        publisher: metadata.publisher,
        description: metadata.description,
        language: metadata.language,
        isbn: metadata.isbn,
        asin: metadata.asin,
        publication_date: metadata.publication_date,
        subjects: metadata.subjects,
        identifier: metadata.identifier,
        cover_image: None,
        doc_type: None,
    };
    let result = match kindling::mobi_rewrite::rewrite_mobi_metadata_bytes(input, &updates) {
        Ok(result) => result,
        Err(RewriteError::DrmEncrypted) => {
            return Reply::error(
                "drmProtected",
                "DRM-protected Kindle files cannot be edited.",
            );
        }
        Err(error) => return Reply::error("conversionFailed", &error.to_string()),
    };
    if result.bytes.len() > request.output_limit {
        return Reply::error("limitExceeded", "Output exceeds the byte limit.");
    }
    let changes: Vec<Value> = result
        .changes
        .iter()
        .map(|change| match change {
            ExthChange::Added { exth_type, .. } => json!({"record": exth_type, "action": "added"}),
            ExthChange::Replaced { exth_type, .. } => {
                json!({"record": exth_type, "action": "replaced"})
            }
            ExthChange::Removed { exth_type, .. } => {
                json!({"record": exth_type, "action": "removed"})
            }
        })
        .collect();
    Reply {
        metadata: json!({"ok": true, "version": "0.46.2", "format": request.format,
            "noOp": result.no_op, "changes": changes, "warnings": []})
        .to_string()
        .into_bytes(),
        data: result.bytes,
    }
}

/// Return ABI 1; capability probing must check this before accepting the asset.
#[unsafe(no_mangle)]
pub extern "C" fn crisp_metadata_abi() -> u32 {
    1
}

/// Allocate a zero-filled input buffer. Only the bundled worker calls this ABI.
#[unsafe(no_mangle)]
pub extern "C" fn crisp_metadata_alloc(length: usize) -> *mut u8 {
    if length == 0 || length > MAX_INPUT {
        return std::ptr::null_mut();
    }
    Box::into_raw(vec![0u8; length].into_boxed_slice()) as *mut u8
}

/// # Safety
/// `pointer` and `length` must be the unchanged pair returned by `alloc`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crisp_metadata_free(pointer: *mut u8, length: usize) {
    if !pointer.is_null() {
        unsafe {
            drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
                pointer, length,
            )));
        }
    }
}

/// # Safety
/// Both input ranges must be live buffers allocated by this module.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crisp_metadata_rewrite(
    input: *const u8,
    input_length: usize,
    request: *const u8,
    request_length: usize,
) -> *mut Reply {
    let reply = if input.is_null()
        || request.is_null()
        || input_length > MAX_INPUT
        || request_length > MAX_JSON
    {
        Reply::error(
            "limitExceeded",
            "Input exceeds the browser metadata limits.",
        )
    } else {
        rewrite(
            unsafe { std::slice::from_raw_parts(input, input_length) },
            unsafe { std::slice::from_raw_parts(request, request_length) },
        )
    };
    Box::into_raw(Box::new(reply))
}

/// # Safety
/// `reply` must be the live handle returned by `rewrite`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crisp_metadata_reply_json(reply: *const Reply) -> *const u8 {
    unsafe { (*reply).metadata.as_ptr() }
}
/// # Safety
/// `reply` must be the live handle returned by `rewrite`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crisp_metadata_reply_json_length(reply: *const Reply) -> usize {
    unsafe { (*reply).metadata.len() }
}
/// # Safety
/// `reply` must be the live handle returned by `rewrite`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crisp_metadata_reply_data(reply: *const Reply) -> *const u8 {
    unsafe { (*reply).data.as_ptr() }
}
/// # Safety
/// `reply` must be the live handle returned by `rewrite`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crisp_metadata_reply_data_length(reply: *const Reply) -> usize {
    unsafe { (*reply).data.len() }
}
/// # Safety
/// `reply` must be a live handle returned by `rewrite`, freed exactly once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crisp_metadata_reply_free(reply: *mut Reply) {
    if !reply.is_null() {
        unsafe {
            drop(Box::from_raw(reply));
        }
    }
}
