//! Scratch benchmark only. No production dependency or ABI commitment.
//! The C ABI exports bounded immutable batches and explicitly owned handles.
use std::collections::HashSet;
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{Instant, UNIX_EPOCH};

#[path = "../reference/index.rs"]
pub mod catalog_index;
// The production scanner refers to super::index.
pub use catalog_index as index;
#[path = "../reference/scan.rs"]
pub mod catalog_scan;

const MAX_ENTRIES: usize = 200_000;
const MAX_DEPTH: usize = 200;
const MAX_ISSUES: usize = 1_000;
const MAX_BYTES: u64 = 9_007_199_254_740_991;
const MEMORY_BUDGET: usize = 128 * 1024 * 1024;
const PAGE_BYTES: usize = 64 * 1024;
const PAGE_ROWS: usize = 500;

#[derive(Debug)]
pub struct Node {
    pub parent: i32,
    pub path: PathBuf,
    pub name: String,
    // 0 = file or unknown non-directory, 1 = directory, 2 = skipped link.
    pub kind: u8,
    pub size: Option<u64>,
    pub mtime: Option<i64>,
    pub complete: bool,
    pub children: Vec<usize>,
    pub bytes: u64,
    pub files: u32,
    pub folders: u32,
    pub unknown: u32,
    pub links: u32,
}

impl Node {
    fn new(parent: i32, path: PathBuf, kind: u8) -> Self {
        let name = path.file_name().and_then(|s| s.to_str())
            .unwrap_or_else(|| path.to_str().unwrap_or("/")).to_owned();
        Self { parent, path, name, kind, size: None, mtime: None,
            complete: kind == 2, children: Vec::new(), bytes: 0,
            files: 0, folders: 0, unknown: 0, links: 0 }
    }
}

#[derive(Debug)]
pub struct Issue {
    pub path: String,
    pub message: String,
    // Root unavailable, unreadable directory, invalid entry, depth, entry, bytes.
    pub code: u32,
}

#[derive(Debug)]
pub struct Report {
    pub nodes: Vec<Node>,
    pub issues: Vec<Issue>,
    pub suppressed: u64,
    pub cancelled: bool,
    pub limited: bool,
}

impl Report {
    fn issue(&mut self, path: &Path, code: u32, message: impl ToString) {
        if self.issues.len() < MAX_ISSUES {
            self.issues.push(Issue {
                path: path.to_string_lossy().chars().take(16_384).collect(),
                message: message.to_string().chars().take(2_048).collect(),
                code,
            });
        } else { self.suppressed += 1; }
    }
    pub fn root(&self) -> &Node { &self.nodes[0] }
    pub fn flags(&self) -> u64 {
        u64::from(self.cancelled) | (u64::from(self.limited) << 1)
            | (u64::from(!self.root().complete) << 2)
    }
}

fn mtime(meta: &fs::Metadata) -> Option<i64> {
    let elapsed = meta.modified().ok()?.duration_since(UNIX_EPOCH).ok()?;
    i64::try_from(elapsed.as_micros()).ok()
}

fn kind(ty: fs::FileType) -> u8 {
    if ty.is_dir() { 1 } else if ty.is_symlink() { 2 } else { 0 }
}

// Mirrors the native adapter's parent/initial/stat/final checks. The extra
// worker pre/post directory checks are done by scan_tree below.
fn checked_directory(path: &Path, strict: bool) -> std::io::Result<fs::Metadata> {
    if strict {
        if let Some(parent) = path.parent() {
            let _ = fs::symlink_metadata(parent)?;
            if !fs::symlink_metadata(parent)?.is_dir() {
                return Err(std::io::Error::other("Parent is not a real directory"));
            }
        }
        if !fs::symlink_metadata(path)?.is_dir() {
            return Err(std::io::Error::other("Directory changed before descent"));
        }
        let meta = fs::metadata(path)?;
        if !meta.is_dir() || !fs::symlink_metadata(path)?.is_dir() {
            return Err(std::io::Error::other("Directory changed during stat"));
        }
        Ok(meta)
    } else {
        let meta = fs::symlink_metadata(path)?;
        if !meta.is_dir() {
            return Err(std::io::Error::other("Not a real directory"));
        }
        Ok(meta)
    }
}

pub fn serial_catalog(root: &Path) -> std::io::Result<index::FileIndex> {
    if !fs::symlink_metadata(root)?.is_dir() {
        return Err(std::io::Error::other("Not a real directory"));
    }
    let mut result = index::FileIndex::new(root.to_owned(), cfg!(windows));
    let mut pending = vec![root.to_owned()];
    while let Some(directory) = pending.pop() {
        for item in fs::read_dir(directory)? {
            let item = item?;
            let ty = item.file_type()?;
            let path = item.path();
            if ty.is_dir() { pending.push(path); }
            else if ty.is_file() {
                let meta = fs::symlink_metadata(&path)?;
                result.add(index::FileEntry::new(path, meta.len(),
                    mtime(&meta).unwrap_or(0).div_euclid(1_000_000) as u32));
            }
        }
    }
    Ok(result)
}

pub fn scan_tree(root: &Path, strict: bool, cancel: &AtomicBool,
                 progress: &AtomicU64) -> Report {
    let mut report = Report { nodes: vec![Node::new(-1, root.to_owned(), 1)],
        issues: Vec::new(), suppressed: 0, cancelled: false, limited: false };
    if !root.is_absolute() || root.to_str().is_none()
        || root.components().any(|c| matches!(c, Component::CurDir | Component::ParentDir)) {
        report.issue(root, 0, "Expected a normalized absolute UTF-8 path");
        return report;
    }
    let mut pending = vec![(0usize, 0usize)];
    let mut seen = HashSet::from([root.to_owned()]);
    let mut retained_bytes = 0usize;
    let mut global_size = 0u64;
    'walk: while let Some((parent, depth)) = pending.pop() {
        if cancel.load(Ordering::Relaxed) { report.cancelled = true; break; }
        let directory = report.nodes[parent].path.clone();
        let meta = match checked_directory(&directory, strict) {
            Ok(m) => m,
            Err(error) => { report.issue(&directory, if parent == 0 {0} else {1}, error); continue; }
        };
        report.nodes[parent].mtime = mtime(&meta);
        if strict && !fs::symlink_metadata(&directory).is_ok_and(|m| m.is_dir()) {
            report.issue(&directory, 1, "Directory changed before enumeration");
            continue;
        }
        let reader = match fs::read_dir(&directory) {
            Ok(r) => r,
            Err(error) => { report.issue(&directory, 1, error); continue; }
        };
        let mut fresh = Vec::new();
        let mut directory_complete = true;
        for entry in reader {
            if cancel.load(Ordering::Relaxed) { report.cancelled = true; break; }
            if report.nodes.len() + fresh.len() > MAX_ENTRIES {
                report.limited = true;
                directory_complete = false;
                report.issue(&directory, 4, "Entry limit");
                break;
            }
            let entry = match entry {
                Ok(e) => e,
                Err(error) => {
                    directory_complete = false; report.issue(&directory, 2, error); continue;
                }
            };
            let path = entry.path();
            let ty = match entry.file_type() {
                Ok(t) => t,
                Err(error) => {
                    directory_complete = false; report.issue(&path, 2, error); continue;
                }
            };
            if path.to_str().is_none() || path.parent() != Some(directory.as_path())
                || path.strip_prefix(root).is_err() || !seen.insert(path.clone()) {
                directory_complete = false;
                report.issue(&path, 2, "Invalid or duplicate child path"); continue;
            }
            let mut node = Node::new(parent as i32, path, kind(ty));
            retained_bytes += 256 + node.path.as_os_str().len() * 2 + node.name.len();
            if retained_bytes > MEMORY_BUDGET {
                report.limited = true; directory_complete = false;
                report.issue(&directory, 4, "Metadata memory budget"); break;
            }
            if node.kind != 2 {
                let metadata = if strict { fs::metadata(&node.path) }
                    else { fs::symlink_metadata(&node.path) };
                let metadata = metadata.and_then(|m| {
                    let expected_type = if ty.is_file() { m.is_file() }
                        else if ty.is_dir() { m.is_dir() } else { false };
                    let post_matches = if strict {
                        let post = fs::symlink_metadata(&node.path)?;
                        if ty.is_file() { post.is_file() }
                        else if ty.is_dir() { post.is_dir() } else { false }
                    } else { true };
                    if !expected_type || !post_matches {
                        Err(std::io::Error::other("Entry changed or has unsupported type"))
                    } else { Ok(m) }
                });
                match metadata {
                    Ok(m) => {
                        node.mtime = mtime(&m);
                        if ty.is_file() {
                            node.size = (m.len() <= MAX_BYTES).then_some(m.len());
                            node.complete = node.size.is_some();
                        }
                    }
                    Err(error) => {
                        directory_complete = false; report.issue(&node.path, 2, error);
                    }
                }
            }
            fresh.push(node);
        }
        if strict && !fs::symlink_metadata(&directory).is_ok_and(|m| m.is_dir()) {
            report.issue(&directory, 1, "Directory changed during enumeration");
            continue;
        }
        report.nodes[parent].complete = directory_complete && !report.cancelled;
        for mut node in fresh {
            let index = report.nodes.len();
            if let Some(bytes) = node.size {
                if global_size.checked_add(bytes).is_none_or(|v| v > MAX_BYTES) {
                    node.size = None; node.complete = false; report.limited = true;
                    report.issue(&node.path, 5, "Exact byte limit");
                } else { global_size += bytes; }
            }
            if node.kind == 1 {
                if depth >= MAX_DEPTH {
                    report.limited = true;
                    report.issue(&node.path, 3, "Depth limit");
                } else { pending.push((index, depth + 1)); }
            }
            report.nodes[parent].children.push(index);
            report.nodes.push(node);
            progress.store(report.nodes.len() as u64, Ordering::Relaxed);
        }
        if report.cancelled || report.limited { break 'walk; }
    }
    for index in (0..report.nodes.len()).rev() {
        let mut children = std::mem::take(&mut report.nodes[index].children);
        let mut bytes = 0u64;
        let (mut files, mut folders, mut unknown, mut links) = (0, 0, 0, 0);
        let mut complete = report.nodes[index].complete;
        for &child in &children {
            let n = &report.nodes[child];
            bytes += n.bytes; files += n.files;
            folders += n.folders + u32::from(n.kind == 1);
            unknown += n.unknown; links += n.links; complete &= n.complete;
        }
        children.sort_by(|&a, &b| report.nodes[b].bytes.cmp(&report.nodes[a].bytes)
            .then_with(|| report.nodes[a].path.cmp(&report.nodes[b].path)));
        let n = &mut report.nodes[index];
        if n.kind == 0 {
            bytes = n.size.unwrap_or(0); files = 1; unknown = u32::from(n.size.is_none());
        } else if n.kind == 2 { links = 1; }
        n.bytes = bytes; n.files = files; n.folders = folders;
        n.unknown = unknown; n.links = links; n.complete = complete;
        n.children = children;
    }
    if report.cancelled || report.limited { report.nodes[0].complete = false; }
    report
}

pub struct Packed {
    pub pages: Vec<Vec<u8>>,
    pub metrics: [u64; 10],
}

fn push_u32(buf: &mut Vec<u8>, value: u32) { buf.extend(value.to_le_bytes()); }
fn push_u64(buf: &mut Vec<u8>, value: u64) { buf.extend(value.to_le_bytes()); }
fn page(kind: u32) -> Vec<u8> {
    let mut out = Vec::with_capacity(PAGE_BYTES);
    push_u32(&mut out, 0x4353_434e); push_u32(&mut out, 1);
    push_u32(&mut out, kind); push_u32(&mut out, 0); out
}
fn flush_page(pages: &mut Vec<Vec<u8>>, current: &mut Vec<u8>, rows: &mut u32, kind: u32) {
    if *rows == 0 { return; }
    current[12..16].copy_from_slice(&rows.to_le_bytes());
    pages.push(std::mem::replace(current, page(kind))); *rows = 0;
}

pub fn pack(report: &Report, scan_ns: u64) -> Result<Packed, String> {
    let started = Instant::now();
    let mut pages = Vec::new();
    let mut current = page(1);
    let mut count = 0;
    // Publish nodes in sorted tree order with new parent IDs, so Dart need not
    // sort the completed tree a second time.
    let mut pending = vec![(0usize, -1i32)];
    let mut next = 0i32;
    while let Some((source, parent)) = pending.pop() {
        let n = &report.nodes[source];
        let mut row = Vec::with_capacity(52 + n.name.len());
        row.extend(parent.to_le_bytes());
        row.push(n.kind);
        row.push(u8::from(n.complete) | (u8::from(n.size.is_some()) << 1)
            | (u8::from(n.mtime.is_some()) << 2));
        row.extend([0, 0]);
        push_u64(&mut row, n.size.unwrap_or(0));
        row.extend(n.mtime.unwrap_or(0).to_le_bytes());
        push_u64(&mut row, n.bytes);
        for value in [n.files, n.folders, n.unknown, n.links, n.name.len() as u32] {
            push_u32(&mut row, value);
        }
        row.extend(n.name.as_bytes());
        if row.len() + 16 > PAGE_BYTES { return Err("Record too large".into()); }
        if count == PAGE_ROWS as u32 || current.len() + row.len() > PAGE_BYTES {
            flush_page(&mut pages, &mut current, &mut count, 1);
        }
        current.extend(row); count += 1;
        for &child in n.children.iter().rev() { pending.push((child, next)); }
        next += 1;
    }
    flush_page(&mut pages, &mut current, &mut count, 1);
    current = page(2);
    for issue in &report.issues {
        let mut row = Vec::new();
        for value in [issue.code, issue.path.len() as u32, issue.message.len() as u32] {
            push_u32(&mut row, value);
        }
        row.extend(issue.path.as_bytes()); row.extend(issue.message.as_bytes());
        if row.len() + 16 > PAGE_BYTES { return Err("Issue too large".into()); }
        if count == PAGE_ROWS as u32 || current.len() + row.len() > PAGE_BYTES {
            flush_page(&mut pages, &mut current, &mut count, 2);
        }
        current.extend(row); count += 1;
    }
    flush_page(&mut pages, &mut current, &mut count, 2);
    let payload: usize = pages.iter().map(Vec::len).sum();
    if payload > MEMORY_BUDGET || pages.len() > 2_048 {
        return Err("Packed result exceeds limit".into());
    }
    let n = report.root();
    Ok(Packed { pages, metrics: [scan_ns, started.elapsed().as_nanos() as u64,
        n.files as u64, n.folders as u64, n.bytes, report.nodes.len() as u64,
        report.issues.len() as u64, report.suppressed, report.flags(), payload as u64] })
}

/// C ownership contract: one run at a time; cancel/progress may run concurrently.
/// Page views are immutable after run returns. Destroy only after run and all
/// page reads complete. Never retain a page pointer after destroy.
pub struct Job {
    cancel: AtomicBool,
    progress: AtomicU64,
    running: AtomicBool,
    result: Mutex<Option<Packed>>,
}

#[no_mangle]
pub extern "C" fn cc_create() -> *mut Job {
    Box::into_raw(Box::new(Job { cancel: AtomicBool::new(false),
        progress: AtomicU64::new(0), running: AtomicBool::new(false),
        result: Mutex::new(None) }))
}
#[no_mangle]
pub unsafe extern "C" fn cc_input_alloc(length: usize) -> *mut u8 {
    if length > 32_768 { return std::ptr::null_mut(); }
    Box::into_raw(vec![0; length].into_boxed_slice()) as *mut u8
}
#[no_mangle]
pub unsafe extern "C" fn cc_input_free(ptr: *mut u8, length: usize) {
    if !ptr.is_null() { drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, length))); }
}
#[no_mangle]
pub unsafe extern "C" fn cc_run(job: *mut Job, root: *const u8, length: usize, strict: u32) -> i32 {
    if job.is_null() || root.is_null() || length == 0 || length > 32_768 { return 2; }
    let job = &*job;
    if job.running.swap(true, Ordering::AcqRel) { return 2; }
    let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let root = std::str::from_utf8(std::slice::from_raw_parts(root, length)).map_err(|_| ())?;
        if root.contains('\0') { return Err(()); }
        let started = Instant::now();
        let report = scan_tree(Path::new(root), strict != 0, &job.cancel, &job.progress);
        let packed = pack(&report, started.elapsed().as_nanos() as u64).map_err(|_| ())?;
        *job.result.lock().map_err(|_| ())? = Some(packed);
        Ok(())
    }));
    job.running.store(false, Ordering::Release);
    match outcome { Ok(Ok(())) => 0, Ok(Err(())) => 2, Err(_) => 3 }
}
#[no_mangle]
pub unsafe extern "C" fn cc_cancel(job: *const Job) {
    if let Some(job) = job.as_ref() { job.cancel.store(true, Ordering::Relaxed); }
}
#[no_mangle]
pub unsafe extern "C" fn cc_progress(job: *const Job) -> u64 {
    job.as_ref().map(|j| j.progress.load(Ordering::Relaxed)).unwrap_or(0)
}
#[no_mangle]
pub unsafe extern "C" fn cc_metric(job: *const Job, metric: usize) -> u64 {
    let Some(job) = job.as_ref() else { return 0 };
    let Ok(guard) = job.result.lock() else { return 0 };
    guard.as_ref().and_then(|r| r.metrics.get(metric).copied()).unwrap_or(0)
}
#[no_mangle]
pub unsafe extern "C" fn cc_pages(job: *const Job) -> usize {
    let Some(job) = job.as_ref() else { return 0 };
    let Ok(guard) = job.result.lock() else { return 0 };
    guard.as_ref().map(|r| r.pages.len()).unwrap_or(0)
}
#[no_mangle]
pub unsafe extern "C" fn cc_page_ptr(job: *const Job, index: usize) -> *const u8 {
    let Some(job) = job.as_ref() else { return std::ptr::null() };
    let Ok(guard) = job.result.lock() else { return std::ptr::null() };
    guard.as_ref().and_then(|r| r.pages.get(index)).map(|p| p.as_ptr()).unwrap_or(std::ptr::null())
}
#[no_mangle]
pub unsafe extern "C" fn cc_page_len(job: *const Job, index: usize) -> usize {
    let Some(job) = job.as_ref() else { return 0 };
    let Ok(guard) = job.result.lock() else { return 0 };
    guard.as_ref().and_then(|r| r.pages.get(index)).map(Vec::len).unwrap_or(0)
}
#[no_mangle]
pub unsafe extern "C" fn cc_destroy(job: *mut Job) {
    if !job.is_null() && !(*job).running.load(Ordering::Acquire) { drop(Box::from_raw(job)); }
}

