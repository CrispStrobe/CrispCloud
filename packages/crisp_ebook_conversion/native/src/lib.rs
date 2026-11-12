//! Bounded, offline adapter around pinned MIT Kindling. It only writes inside
//! the job directory created by Dart. Native jobs never touch the user's file.
use std::collections::{HashMap, HashSet};
use std::ffi::{CString, c_char};
use std::fs;
use std::io::{Cursor, Read};
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use kindling::extracted::ExtractedEpub;
use kindling::mobi_rewrite::{ExthChange, MetadataUpdates};
use percent_encoding::percent_decode_str;
use serde::Deserialize;
use serde_json::{Value, json};

const VERSION: &[u8] = b"crisp-kindling 1 (Kindling 0.46.2)\0";
const MAX_JSON: usize = 131_072;

#[derive(Debug)]
struct Failure(&'static str, String);
type Result<T> = std::result::Result<T, Failure>;
fn fail(code: &'static str, message: impl Into<String>) -> Failure {
    Failure(code, message.into())
}
fn io_error(e: impl std::fmt::Display) -> Failure {
    fail("invalidInput", e.to_string())
}
fn checkpoint(cancel: &AtomicBool) -> Result<()> {
    if cancel.load(Ordering::Relaxed) {
        Err(fail("cancelled", "Conversion was cancelled."))
    } else {
        Ok(())
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    work_dir: String,
    operation: String,
    format: String,
    #[serde(default)]
    metadata: Metadata,
    #[serde(default)]
    cover: bool,
    limits: Limits,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Limits {
    input_bytes: u64,
    output_bytes: u64,
    expanded_bytes: u64,
    entry_bytes: u64,
    entries: usize,
    image_pixels: u64,
}
impl Limits {
    fn validate(&self) -> Result<()> {
        if self.input_bytes == 0
            || self.input_bytes > 256 * 1024 * 1024
            || self.output_bytes == 0
            || self.output_bytes > 512 * 1024 * 1024
            || self.expanded_bytes == 0
            || self.expanded_bytes > 512 * 1024 * 1024
            || self.entry_bytes == 0
            || self.entry_bytes > 64 * 1024 * 1024
            || self.entries == 0
            || self.entries > 20_000
            || self.image_pixels == 0
            || self.image_pixels > 100_000_000
        {
            return Err(fail("limitExceeded", "Unsupported conversion limits."));
        }
        Ok(())
    }
}

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

fn read_bounded(path: &Path, max: u64) -> Result<Vec<u8>> {
    let meta = fs::symlink_metadata(path).map_err(io_error)?;
    if !meta.is_file() || meta.file_type().is_symlink() {
        return Err(fail(
            "invalidInput",
            "Input must be a regular private snapshot.",
        ));
    }
    if meta.len() > max {
        return Err(fail("limitExceeded", "Input exceeds the byte limit."));
    }
    let mut data = Vec::new();
    fs::File::open(path)
        .map_err(io_error)?
        .take(max + 1)
        .read_to_end(&mut data)
        .map_err(io_error)?;
    if data.len() as u64 > max {
        return Err(fail("limitExceeded", "Input exceeds the byte limit."));
    }
    Ok(data)
}

/// Resolve an EPUB-relative URL without letting it leave the extracted archive.
/// Resolve once-decoded and twice-decoded forms because upstream decodes hrefs.
fn confined_reference(root: &Path, base: &Path, reference: &str) -> Result<()> {
    let reference = reference.split(['#', '?']).next().unwrap_or("");
    if reference.is_empty() {
        return Ok(());
    }
    let mut decoded = reference.to_owned();
    for _ in 0..3 {
        if decoded.contains('\0')
            || decoded.contains('\\')
            || decoded.starts_with('/')
            || decoded.split('/').next().unwrap_or("").contains(':')
        {
            return Err(fail("invalidInput", "An EPUB resource has an unsafe path."));
        }
        let mut candidate = base.to_path_buf();
        for part in Path::new(&decoded).components() {
            match part {
                Component::Normal(p) => candidate.push(p),
                Component::CurDir => (),
                Component::ParentDir => {
                    if !candidate.pop() || !candidate.starts_with(root) {
                        return Err(fail("invalidInput", "An EPUB resource leaves its archive."));
                    }
                }
                _ => {
                    return Err(fail(
                        "invalidInput",
                        "An EPUB resource has an absolute path.",
                    ));
                }
            }
        }
        if !candidate.starts_with(root) {
            return Err(fail("invalidInput", "An EPUB resource leaves its archive."));
        }
        let next = percent_decode_str(&decoded)
            .decode_utf8()
            .map_err(|_| fail("invalidInput", "Invalid UTF-8 in EPUB resource URL."))?
            .into_owned();
        if next == decoded {
            break;
        }
        decoded = next;
    }
    Ok(())
}

fn inspect_markup(root: &Path, path: &Path, data: &[u8]) -> Result<()> {
    let text = std::str::from_utf8(data).map_err(|_| {
        fail(
            "invalidInput",
            "EPUB markup must use UTF-8 for Kindle export.",
        )
    })?;
    // roxmltree never fetches external DTDs. Accept standard EPUB2 XHTML
    // declarations but reject entity declarations and inherited base URLs.
    if text.to_ascii_uppercase().contains("<!ENTITY") {
        return Err(fail(
            "invalidInput",
            "XML entity declarations are unsupported for export.",
        ));
    }
    let xml = roxmltree::Document::parse_with_options(
        text,
        roxmltree::ParsingOptions {
            allow_dtd: true,
            nodes_limit: 1_000_000,
            ..Default::default()
        },
    )
    .map_err(|e| fail("invalidInput", format!("EPUB XML is not well formed: {e}")))?;
    let base = path.parent().unwrap_or(root);
    for node in xml.descendants().filter(|n| n.is_element()) {
        for attr in node.attributes() {
            if attr.name() == "base" {
                return Err(fail(
                    "invalidInput",
                    "EPUB base URL overrides are unsupported.",
                ));
            }
            if matches!(attr.name(), "href" | "src" | "full-path" | "URI" | "poster") {
                let value = attr.value();
                // Only hyperlinks may leave the archive; the builder never
                // fetches remote resources. Other resource schemes are rejected.
                if node.tag_name().name() == "a"
                    && attr.name() == "href"
                    && ["https:", "http:", "mailto:", "tel:"]
                        .iter()
                        .any(|scheme| value.to_ascii_lowercase().starts_with(scheme))
                {
                    continue;
                }
                // Encryption URIs are inspected separately; these are algorithms.
                if attr.name() == "URI" && node.tag_name().name() != "CipherReference" {
                    continue;
                }
                confined_reference(root, base, value)?;
            }
        }
    }
    inspect_css(root, base, text)
}

fn inspect_css(root: &Path, base: &Path, text: &str) -> Result<()> {
    static URLS: OnceLock<regex::Regex> = OnceLock::new();
    let re = URLS.get_or_init(|| {
        regex::Regex::new(r#"(?i)(?:url\(\s*["']?|@import\s+["'])([^"')\s]+)"#).unwrap()
    });
    for m in re.captures_iter(text) {
        confined_reference(root, base, &m[1])?;
    }
    Ok(())
}

fn inspect_image(data: &[u8], limits: &Limits) -> Result<()> {
    let format = match image::guess_format(data) {
        Ok(f) => f,
        Err(_) => return Ok(()), // SVG/fonts/etc are not raster images.
    };
    let (width, height) = image::ImageReader::with_format(Cursor::new(data), format)
        .into_dimensions()
        .map_err(io_error)?;
    if (width as u64).saturating_mul(height as u64) > limits.image_pixels {
        return Err(fail(
            "limitExceeded",
            "Image pixel count exceeds the conversion limit.",
        ));
    }
    Ok(())
}

fn unpack_epub(root: &Path, data: &[u8], limits: &Limits, cancel: &AtomicBool) -> Result<PathBuf> {
    let target = root.join("book");
    fs::create_dir(&target).map_err(io_error)?;
    let mut zip = zip::ZipArchive::new(Cursor::new(data)).map_err(io_error)?;
    if zip.len() > limits.entries {
        return Err(fail("limitExceeded", "Too many EPUB archive members."));
    }
    let mut total = 0u64;
    let mut names = HashSet::new();
    let mut inspect = Vec::new();
    for i in 0..zip.len() {
        checkpoint(cancel)?;
        let mut file = zip.by_index(i).map_err(io_error)?;
        let name = file.name().map_err(io_error)?.to_owned();
        if name.contains('\\')
            || name.contains('\0')
            || name.starts_with('/')
            || name.split('/').next().unwrap_or("").contains(':')
            || file
                .unix_mode()
                .map(|m| m & 0o170000 == 0o120000)
                .unwrap_or(false)
        {
            return Err(fail("invalidInput", "Unsafe EPUB archive member."));
        }
        let relative = file
            .enclosed_name()
            .ok_or_else(|| fail("invalidInput", "EPUB archive path traversal."))?;
        if !names.insert(relative.to_string_lossy().to_lowercase()) {
            return Err(fail(
                "invalidInput",
                "Duplicate or case-colliding EPUB archive members.",
            ));
        }
        total = total
            .checked_add(file.size())
            .ok_or_else(|| fail("limitExceeded", "Archive size overflow."))?;
        if file.size() > limits.entry_bytes || total > limits.expanded_bytes {
            return Err(fail(
                "limitExceeded",
                "Expanded EPUB exceeds the conversion limit.",
            ));
        }
        let path = target.join(relative);
        if file.is_dir() {
            fs::create_dir_all(&path).map_err(io_error)?;
            continue;
        }
        let mut bytes = Vec::new();
        file.by_ref()
            .take(limits.entry_bytes + 1)
            .read_to_end(&mut bytes)
            .map_err(io_error)?;
        if bytes.len() as u64 != file.size() || bytes.len() as u64 > limits.entry_bytes {
            return Err(fail(
                "limitExceeded",
                "EPUB archive member size is inconsistent.",
            ));
        }
        inspect_image(&bytes, limits)?;
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(io_error)?;
        }
        fs::write(&path, &bytes).map_err(io_error)?;
        inspect.push(path);
    }
    if read_bounded(&target.join("mimetype"), 128)? != b"application/epub+zip" {
        return Err(fail(
            "invalidInput",
            "The archive is not an EPUB container.",
        ));
    }
    if target.join("META-INF/rights.xml").exists() {
        return Err(fail(
            "drmProtected",
            "DRM-protected EPUBs cannot be exported.",
        ));
    }
    let encryption = target.join("META-INF/encryption.xml");
    if encryption.exists() {
        let text = fs::read_to_string(&encryption).map_err(io_error)?;
        let doc = roxmltree::Document::parse(&text).map_err(io_error)?;
        let algorithms: Vec<_> = doc
            .descendants()
            .filter(|n| n.tag_name().name() == "EncryptionMethod")
            .filter_map(|n| n.attribute("Algorithm"))
            .collect();
        if algorithms.is_empty()
            || algorithms.iter().any(|a| {
                !matches!(
                    *a,
                    "http://www.idpf.org/2008/embedding" | "http://ns.adobe.com/pdf/enc#RC"
                )
            })
        {
            return Err(fail(
                "drmProtected",
                "Encrypted EPUB content is unsupported.",
            ));
        }
    }
    for path in inspect {
        checkpoint(cancel)?;
        let ext = path
            .extension()
            .and_then(|p| p.to_str())
            .unwrap_or("")
            .to_lowercase();
        if matches!(
            ext.as_str(),
            "xml" | "opf" | "xhtml" | "html" | "htm" | "ncx" | "svg"
        ) {
            inspect_markup(&target, &path, &read_bounded(&path, limits.entry_bytes)?)?;
        } else if ext == "css" {
            let text = fs::read_to_string(&path).map_err(io_error)?;
            inspect_css(&target, path.parent().unwrap_or(&target), &text)?;
        }
    }
    let container = fs::read_to_string(target.join("META-INF/container.xml")).map_err(io_error)?;
    let doc = roxmltree::Document::parse(&container).map_err(io_error)?;
    let rootfile = doc
        .descendants()
        .find(|n| n.tag_name().name() == "rootfile")
        .and_then(|n| n.attribute("full-path"))
        .ok_or_else(|| fail("invalidInput", "EPUB container has no rootfile."))?;
    confined_reference(&target, &target, rootfile)?;
    let opf = target.join(
        percent_decode_str(rootfile)
            .decode_utf8()
            .map_err(io_error)?
            .as_ref(),
    );
    if !opf.is_file() {
        return Err(fail("invalidInput", "EPUB package is missing."));
    }
    Ok(opf)
}

fn process(request: Request, cancel: &AtomicBool) -> Result<Value> {
    request.limits.validate()?;
    checkpoint(cancel)?;
    if !matches!(request.format.as_str(), "azw3" | "mobi") {
        return Err(fail(
            "unsupportedFormat",
            "Only AZW3 and legacy MOBI export are supported.",
        ));
    }
    let root = PathBuf::from(&request.work_dir);
    if !root.is_absolute()
        || fs::symlink_metadata(&root)
            .map_err(io_error)?
            .file_type()
            .is_symlink()
    {
        return Err(fail(
            "invalidInput",
            "Conversion requires a private absolute job directory.",
        ));
    }
    let root = root.canonicalize().map_err(io_error)?;
    let output = root.join(format!("output.{}", request.format));
    if output.exists() || fs::symlink_metadata(&output).is_ok() {
        return Err(fail("invalidInput", "Conversion output already exists."));
    }
    let mut warnings = Vec::new();
    let mut changes = Vec::new();
    let mut no_op = false;
    match request.operation.as_str() {
        "export" => {
            let input = read_bounded(&root.join("input.epub"), request.limits.input_bytes)?;
            let opf = unpack_epub(&root, &input, &request.limits, cancel)?;
            let book = ExtractedEpub::from_opf_path(&opf).map_err(io_error)?;
            // Repeated spine entries can multiply a small ZIP into enormous
            // generated text. Charge each use before invoking the builder.
            if book.opf.spine_items.len() > request.limits.entries {
                return Err(fail("limitExceeded", "Too many EPUB spine entries."));
            }
            let mut text_budget = 0u64;
            for (_, href) in &book.opf.spine_items {
                let decoded = percent_decode_str(href).decode_utf8().map_err(io_error)?;
                let path = book.opf.base_dir.join(decoded.as_ref());
                text_budget = text_budget
                    .checked_add(fs::metadata(&path).map_err(io_error)?.len())
                    .ok_or_else(|| fail("limitExceeded", "EPUB spine size overflow."))?;
                if text_budget > request.limits.expanded_bytes
                    || text_budget > request.limits.output_bytes
                {
                    return Err(fail(
                        "limitExceeded",
                        "Expanded EPUB spine exceeds its conversion budget.",
                    ));
                }
            }
            checkpoint(cancel)?;
            let report = kindling::validate::validate(&book);
            for finding in &report.findings {
                let message = finding.to_string();
                if warnings.len() < 200 {
                    warnings.push(message);
                }
            }
            if report.error_count() > 0 {
                return Err(fail("validationFailed", warnings.join("\n")));
            }
            checkpoint(cancel)?;
            kindling::mobi::build_mobi_from_extracted(
                &book,
                &output,
                false,
                false,
                Some(&input),
                true,
                false,
                false,
                request.format == "azw3",
                Some("PDOC"),
                true,
                true,
                false,
                false,
                false,
                false,
            )
            .map_err(|e| fail("conversionFailed", e.to_string()))?;
            checkpoint(cancel)?;
            let check = kindling::mobi_check::check_mobi_file(
                &output,
                &kindling::mobi_check::ExpectedMetadata::default(),
            )
            .map_err(io_error)?;
            if check.has_errors() {
                return Err(fail("validationFailed", check.p0_errors.join("\n")));
            }
            warnings.extend(check.warnings);
            warnings.push("Kindle export converts the book; layout and navigation can differ from the source EPUB.".into());
        }
        "metadata" => {
            read_bounded(&root.join("input.mobi"), request.limits.input_bytes)?;
            let m = request.metadata;
            let cover = if request.cover {
                let data = read_bounded(&root.join("cover"), request.limits.entry_bytes)?;
                inspect_image(&data, &request.limits)?;
                Some(data)
            } else {
                None
            };
            let updates = MetadataUpdates {
                title: m.title,
                authors: m.authors,
                publisher: m.publisher,
                description: m.description,
                language: m.language,
                isbn: m.isbn,
                asin: m.asin,
                publication_date: m.publication_date,
                subjects: m.subjects,
                identifier: m.identifier,
                cover_image: cover,
                doc_type: None,
            };
            checkpoint(cancel)?;
            let report = kindling::mobi_rewrite::rewrite_mobi_metadata(
                &root.join("input.mobi"),
                &output,
                &updates,
            )
            .map_err(|e| match e {
                kindling::mobi_rewrite::RewriteError::DrmEncrypted => fail(
                    "drmProtected",
                    "DRM-protected Kindle files cannot be edited.",
                ),
                _ => fail("conversionFailed", e.to_string()),
            })?;
            no_op = report.no_op;
            for change in report.changes {
                changes.push(match change {
                    ExthChange::Added { exth_type, .. } => {
                        json!({"record":exth_type,"action":"added"})
                    }
                    ExthChange::Replaced { exth_type, .. } => {
                        json!({"record":exth_type,"action":"replaced"})
                    }
                    ExthChange::Removed { exth_type, .. } => {
                        json!({"record":exth_type,"action":"removed"})
                    }
                });
            }
            if report.cover_updated {
                warnings.push("Existing HD image-container records are not replaced by metadata cover changes.".into());
            }
        }
        _ => return Err(fail("unsupportedFormat", "Unsupported ebook operation.")),
    }
    checkpoint(cancel)?;
    let bytes = read_bounded(&output, request.limits.output_bytes)?;
    if bytes.len() < 78 || &bytes[60..68] != b"BOOKMOBI" {
        return Err(fail("validationFailed", "Output is not a Kindle ebook."));
    }
    Ok(json!({
        "ok":true, "version":"0.46.2", "format":request.format,
        "warnings":warnings, "changes":changes, "noOp":no_op
    }))
}

/// Request/response surface also used by the separately cancellable desktop helper.
pub fn run_request_json(input: &[u8], cancel: &AtomicBool) -> String {
    let result = std::panic::catch_unwind(|| {
        if input.len() > MAX_JSON {
            return Err(fail("limitExceeded", "Conversion request is too large."));
        }
        let request: Request = serde_json::from_slice(input).map_err(io_error)?;
        process(request, cancel)
    });
    let response = match result {
        Ok(Ok(value)) => value,
        Ok(Err(Failure(code, message))) => {
            json!({"ok":false,"code":code,"message":message.chars().take(32_768).collect::<String>()})
        }
        Err(_) => {
            json!({"ok":false,"code":"conversionFailed","message":"The converter could not process this ebook."})
        }
    };
    response.to_string()
}

struct Job {
    cancelled: AtomicBool,
    result: Mutex<Option<String>>,
}
static JOBS: OnceLock<Mutex<HashMap<u64, Arc<Job>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
fn jobs() -> &'static Mutex<HashMap<u64, Arc<Job>>> {
    JOBS.get_or_init(Default::default)
}

#[unsafe(no_mangle)]
pub extern "C" fn crisp_kindling_version() -> *const c_char {
    VERSION.as_ptr().cast()
}

/// Starts at most one native job. Returns 0 for malformed input or a busy engine.
/// The native thread owns the copied request until a terminal poll.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crisp_kindling_start(data: *const u8, length: usize) -> u64 {
    if data.is_null() || length == 0 || length > MAX_JSON {
        return 0;
    }
    let request = unsafe { std::slice::from_raw_parts(data, length) }.to_vec();
    let mut registry = jobs().lock().unwrap_or_else(|p| p.into_inner());
    if !registry.is_empty() {
        return 0;
    }
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    let job = Arc::new(Job {
        cancelled: AtomicBool::new(false),
        result: Mutex::new(None),
    });
    registry.insert(id, job.clone());
    let spawn = std::thread::Builder::new()
        .name("crisp-ebook".into())
        .spawn(move || {
            let result = run_request_json(&request, &job.cancelled);
            *job.result.lock().unwrap_or_else(|p| p.into_inner()) = Some(result);
        });
    if spawn.is_err() {
        registry.remove(&id);
        return 0;
    }
    id
}

/// Null means running/unknown. A non-null response consumes the finished job.
#[unsafe(no_mangle)]
pub extern "C" fn crisp_kindling_poll(id: u64) -> *mut c_char {
    let mut registry = jobs().lock().unwrap_or_else(|p| p.into_inner());
    let Some(job) = registry.get(&id) else {
        return std::ptr::null_mut();
    };
    let result = job.result.lock().unwrap_or_else(|p| p.into_inner()).take();
    if let Some(result) = result {
        registry.remove(&id);
        return CString::new(result).unwrap().into_raw();
    }
    std::ptr::null_mut()
}

#[unsafe(no_mangle)]
pub extern "C" fn crisp_kindling_cancel(id: u64) {
    if let Some(job) = jobs().lock().unwrap_or_else(|p| p.into_inner()).get(&id) {
        job.cancelled.store(true, Ordering::Relaxed);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn crisp_kindling_free(data: *mut c_char) {
    if !data.is_null() {
        drop(unsafe { CString::from_raw(data) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct TestDirectory(PathBuf);

    impl TestDirectory {
        fn new() -> Self {
            static NEXT_DIRECTORY: AtomicU64 = AtomicU64::new(1);
            let path = std::env::temp_dir().join(format!(
                "crisp-kindling-test-{}-{}",
                std::process::id(),
                NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for TestDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn css_grammar_errors_are_reported_before_export() {
        let root = TestDirectory::new();
        fs::write(
            root.0.join("book.opf"),
            r#"<package xmlns="http://www.idpf.org/2007/opf" version="3.0"
                unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="id">test</dc:identifier><dc:title>Test</dc:title>
                <dc:language>en</dc:language></metadata><manifest>
                <item id="css" href="style.css" media-type="text/css"/>
                </manifest><spine/></package>"#,
        )
        .unwrap();
        // Delimiters are balanced, but an empty selector after the comma is
        // invalid. The former delimiter-only checker accepted this stylesheet.
        fs::write(root.0.join("style.css"), "p, { color: red; }").unwrap();
        let book = ExtractedEpub::from_opf_path(&root.0.join("book.opf")).unwrap();
        assert!(book.css_summary("style.css").unwrap().parse_error.is_some());
    }

    #[test]
    fn paths_cannot_escape_after_percent_decoding() {
        let root = Path::new("/private/book");
        let base = root.join("OEBPS");
        assert!(confined_reference(root, &base, "../images/cover.png#id").is_ok());
        assert!(confined_reference(root, &base, "%252e%252e/%252e%252e/secret").is_err());
        assert!(confined_reference(root, &base, "file:///private/secret").is_err());
        assert!(confined_reference(root, &base, "C:%5csecret").is_err());
    }

    #[test]
    fn standard_epub2_doctype_is_accepted_without_entity_resolution() {
        let root = Path::new("/private/book");
        let xml = br#"<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
            "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
            <html xmlns="http://www.w3.org/1999/xhtml"><body><p>Safe</p></body></html>"#;
        assert!(inspect_markup(root, &root.join("chapter.xhtml"), xml).is_ok());
        let entity = br#"<!DOCTYPE html [<!ENTITY x SYSTEM "file:///private/secret">]>
            <html><body>&x;</body></html>"#;
        assert!(inspect_markup(root, &root.join("chapter.xhtml"), entity).is_err());
    }

    #[test]
    fn css_remote_and_parent_resources_are_rejected() {
        let root = Path::new("/private/book");
        assert!(inspect_css(root, root, "p { background: url(https://host/image); }").is_err());
        assert!(inspect_css(root, root, "@import '../outside.css';").is_err());
        assert!(inspect_css(root, root, "@font-face { src: url(fonts/test.woff); }").is_ok());
    }
}
