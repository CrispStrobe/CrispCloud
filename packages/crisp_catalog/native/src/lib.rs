//! Native metadata-only catalogue backend. No credentials or file contents.
//! CAF interchange reuses the explicitly MIT-licensed CrispSorter crate slice.
use crispcat_format::{
    caf,
    index::{FileEntry, FileIndex},
};
use rusqlite::{params, Connection, OpenFlags};
use serde_json::{json, Value};
use std::{
    ffi::{c_char, CStr, CString},
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;
const MAX_BYTES: u64 = 9_007_199_254_740_991;
const VERSION: i64 = 1;
fn text<'a>(v: &'a Value, key: &str) -> Result<&'a str> {
    v[key]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| format!("Missing {key}").into())
}
fn number(v: &Value, key: &str, default: u64) -> Result<u64> {
    match v.get(key) {
        None => Ok(default),
        Some(x) => x.as_u64().ok_or_else(|| format!("Invalid {key}").into()),
    }
}
fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}
fn utf8(path: &Path) -> Result<&str> {
    path.to_str()
        .ok_or_else(|| "Non-UTF-8 pathname cannot be represented in this catalogue".into())
}
fn relative(path: &Path) -> Result<String> {
    let mut parts = Vec::new();
    for part in path.components() {
        match part {
            std::path::Component::Normal(x) => parts.push(x.to_str().ok_or("Non-UTF-8 pathname")?),
            std::path::Component::CurDir => (),
            _ => return Err("Expected a relative path without '..'".into()),
        }
    }
    Ok(parts.join("/"))
}
fn parent(path: &str) -> &str {
    path.rsplit_once('/').map(|x| x.0).unwrap_or("")
}
fn add_issue(db: &Connection, path: &str, code: &str, detail: &str) -> Result<()> {
    db.execute("UPDATE meta SET issues=issues+1 WHERE id=1", [])?;
    let n: i64 = db.query_row("SELECT issues FROM meta WHERE id=1", [], |r| r.get(0))?;
    if n <= 256 {
        db.execute(
            "INSERT INTO issues VALUES (?1,?2,?3)",
            params![path, code, detail],
        )?;
    }
    db.execute("UPDATE entries SET complete=0 WHERE path=?1", [path])?;
    Ok(())
}
fn create(db: &Connection, root: &str, origin: &str) -> Result<()> {
    db.execute_batch("CREATE TABLE meta(id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL, root TEXT NOT NULL,
        created INTEGER NOT NULL, origin TEXT NOT NULL, issues INTEGER NOT NULL DEFAULT 0,
        skipped_links INTEGER NOT NULL DEFAULT 0, skipped_special INTEGER NOT NULL DEFAULT 0,
        visited INTEGER NOT NULL DEFAULT 0, excluded_catalogue INTEGER NOT NULL DEFAULT 0, complete INTEGER NOT NULL DEFAULT 1, header TEXT);
      CREATE TABLE entries(path TEXT PRIMARY KEY, parent TEXT, kind INTEGER NOT NULL, depth INTEGER NOT NULL,
        bytes INTEGER NOT NULL DEFAULT 0, files INTEGER NOT NULL DEFAULT 0, dirs INTEGER NOT NULL DEFAULT 0,
        complete INTEGER NOT NULL DEFAULT 1, mtime INTEGER);
      CREATE TABLE issues(path TEXT, code TEXT, detail TEXT);")?;
    db.execute(
        "INSERT INTO meta(id,version,root,created,origin) VALUES(1,?1,?2,?3,?4)",
        params![VERSION, root, now(), origin],
    )?;
    db.execute(
        "INSERT INTO entries(path,parent,kind,depth) VALUES('',NULL,1,0)",
        [],
    )?;
    Ok(())
}
fn aggregate(db: &Connection) -> Result<()> {
    // Depth-ordered updates touch each edge once. Do not build the whole tree
    // in the Dart heap or run one subtree query per directory.
    db.execute_batch("CREATE INDEX by_parent ON entries(parent,bytes DESC,path);")?;
    let mut stmt = db.prepare(
        "SELECT path,parent,bytes,files,dirs,complete,kind FROM entries ORDER BY depth DESC",
    )?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let path: String = row.get(0)?;
        if path.is_empty() {
            continue;
        }
        // Values may have changed as deeper descendants were aggregated.
        let (bytes, files, dirs, complete, kind): (i64, i64, i64, bool, i64) = db.query_row(
            "SELECT bytes,files,dirs,complete,kind FROM entries WHERE path=?1",
            [&path],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)),
        )?;
        let par: String = row.get(1)?;
        let old: i64 = db.query_row("SELECT bytes FROM entries WHERE path=?1", [&par], |r| {
            r.get(0)
        })?;
        if bytes > MAX_BYTES as i64 - old {
            return Err(
                "Catalogue exceeds the exact byte-reporting range; previous catalogue preserved"
                    .into(),
            );
        }
        db.execute("UPDATE entries SET bytes=bytes+?1,files=files+?2,dirs=dirs+?3,complete=complete AND ?4 WHERE path=?5",
            params![bytes,files,dirs+i64::from(kind==1),complete,par])?;
    }
    db.execute_batch("CREATE INDEX largest_files ON entries(kind,bytes DESC,path); CREATE INDEX depth_rank ON entries(depth,bytes DESC,path);
      UPDATE meta SET complete=(issues=0 AND (SELECT complete FROM entries WHERE path='')) WHERE id=1;")?;
    Ok(())
}
fn open(path: &str) -> Result<Connection> {
    let db = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    db.pragma_update(None, "query_only", true)?;
    let version: i64 = db.query_row("SELECT version FROM meta WHERE id=1", [], |r| r.get(0))?;
    if version != VERSION {
        return Err("Unsupported catalogue version".into());
    }
    Ok(db)
}
fn info(db: &Connection) -> Result<Value> {
    Ok(db.query_row("SELECT m.root,m.created,m.origin,m.complete,m.issues,m.skipped_links,m.skipped_special,m.visited,e.bytes,e.files,e.dirs,m.excluded_catalogue
      FROM meta m JOIN entries e ON e.path='' WHERE m.id=1", [], |r| Ok(json!({
        "root":r.get::<_,String>(0)?,"indexedAtUnix":r.get::<_,i64>(1)?,"origin":r.get::<_,String>(2)?,
        "complete":r.get::<_,bool>(3)?,"issueCount":r.get::<_,i64>(4)?,"linksSkipped":r.get::<_,i64>(5)?,
        "specialEntriesSkipped":r.get::<_,i64>(6)?,"entriesVisited":r.get::<_,i64>(7)?,
        "bytes":r.get::<_,i64>(8)?,"files":r.get::<_,i64>(9)?,"directories":r.get::<_,i64>(10)?,
        "measurement":"logical_file_bytes","historical":true,"schemaVersion":VERSION,"catalogueFilesSkipped":r.get::<_,i64>(11)?
    })))?)
}
fn staging(
    destination: &Path,
    replace: bool,
    build: impl FnOnce(&mut Connection) -> Result<()>,
) -> Result<Value> {
    if destination.exists() && !replace {
        return Err("Output exists; use --replace to publish a new catalogue".into());
    }
    let dir = destination
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let temp = tempfile::Builder::new()
        .prefix(".crisp-catalog-")
        .tempfile_in(dir)?;
    let mut db = Connection::open(temp.path())?;
    db.execute_batch("PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; BEGIN IMMEDIATE")?;
    build(&mut db)?;
    aggregate(&db)?;
    db.execute_batch("COMMIT; PRAGMA optimize;")?;
    let result = info(&db)?;
    db.close().map_err(|(_, e)| e)?;
    temp.as_file().sync_all()?;
    if replace {
        temp.persist(destination).map_err(|e| e.error)?;
    } else {
        temp.persist_noclobber(destination).map_err(|e| e.error)?;
    }
    Ok(result)
}
fn scan(v: &Value) -> Result<Value> {
    let root = Path::new(text(v, "path")?).canonicalize()?;
    if !root.is_dir() {
        return Err("Choose a directory to index".into());
    }
    let destination = Path::new(text(v, "output")?);
    let absolute_output = destination
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."))
        .canonicalize()?
        .join(destination.file_name().ok_or("Missing output name")?);
    let cap = number(v, "maxEntries", 0)?;
    let depth_cap = number(v, "maxDepth", 0)?;
    staging(destination, v["replace"] == true, |db| {
        create(db, utf8(&root)?, "native_scan")?;
        let staging_path = PathBuf::from(db.path().ok_or("Missing staging database path")?);
        let mut excluded =
            std::collections::HashSet::from([absolute_output.clone(), staging_path.clone()]);
        for base in [&absolute_output, &staging_path] {
            for suffix in ["-journal", "-wal", "-shm"] {
                let mut path = base.as_os_str().to_os_string();
                path.push(suffix);
                excluded.insert(PathBuf::from(path));
            }
        }
        let mut visited = 0u64;
        let mut walker = jwalk::WalkDir::new(&root)
            .skip_hidden(false)
            .follow_links(false)
            .parallelism(jwalk::Parallelism::RayonNewPool(4));
        if depth_cap > 0 {
            walker = walker.max_depth(depth_cap as usize);
        }
        for result in walker {
            if cap > 0 && visited >= cap {
                add_issue(db, "", "entry_limit", "Explicit entry budget reached")?;
                break;
            }
            visited += 1;
            let mut entry = match result {
                Ok(e) => e,
                Err(e) => {
                    add_issue(db, "", "traversal", &e.to_string())?;
                    continue;
                }
            };
            if entry.depth() == 0 {
                if let Some(e) = entry.read_children_error.take() {
                    add_issue(db, "", "unreadable_directory", &e.to_string())?;
                }
                continue;
            }
            let path = entry.path();
            if excluded.contains(&path) {
                db.execute(
                    "UPDATE meta SET excluded_catalogue=excluded_catalogue+1",
                    [],
                )?;
                continue;
            }
            let rel = match path.strip_prefix(&root).ok().and_then(|p| relative(p).ok()) {
                Some(x) => x,
                None => {
                    add_issue(
                        db,
                        "",
                        "unrepresentable_path",
                        "A pathname cannot be represented as UTF-8",
                    )?;
                    continue;
                }
            };
            let par = parent(&rel);
            if entry.file_type().is_symlink() {
                db.execute("UPDATE meta SET skipped_links=skipped_links+1", [])?;
                continue;
            }
            if !entry.file_type().is_dir() && !entry.file_type().is_file() {
                db.execute("UPDATE meta SET skipped_special=skipped_special+1", [])?;
                continue;
            }
            let metadata = match std::fs::symlink_metadata(&path) {
                Ok(x)
                    if (x.is_dir() && entry.file_type().is_dir())
                        || (x.is_file() && entry.file_type().is_file()) =>
                {
                    x
                }
                Ok(_) => {
                    add_issue(
                        db,
                        par,
                        "changed_type",
                        "Entry changed type during scanning",
                    )?;
                    continue;
                }
                Err(e) => {
                    add_issue(db, par, "unreadable_metadata", &e.to_string())?;
                    continue;
                }
            };
            let is_dir = metadata.is_dir();
            if metadata.len() > MAX_BYTES && !is_dir {
                return Err("File exceeds exact byte-reporting bound".into());
            }
            let mtime = metadata
                .modified()
                .ok()
                .and_then(|x| x.duration_since(UNIX_EPOCH).ok())
                .map(|x| x.as_secs());
            db.execute("INSERT INTO entries(path,parent,kind,depth,bytes,files,mtime) VALUES(?1,?2,?3,?4,?5,?6,?7)",
                params![rel,par,i64::from(is_dir),entry.depth() as i64,if is_dir {0}else{metadata.len() as i64},i64::from(!is_dir),mtime.and_then(|x|i64::try_from(x).ok())])?;
            if let Some(e) = entry.read_children_error.take() {
                add_issue(db, &rel, "unreadable_directory", &e.to_string())?;
            }
            if is_dir && depth_cap > 0 && entry.depth() as u64 >= depth_cap {
                add_issue(db, &rel, "depth_limit", "Explicit depth budget reached")?;
            }
        }
        db.execute("UPDATE meta SET visited=?1", [visited as i64])?;
        let issues: i64 = db.query_row("SELECT issues FROM meta WHERE id=1", [], |r| r.get(0))?;
        if issues > 0 && destination.exists() && v["allowPartial"] != true {
            return Err("Incomplete refresh would replace an existing catalogue. Previous catalogue preserved; use --allow-partial only after reviewing the scan limits/access failures".into());
        }
        Ok(())
    })
}
fn import_caf(v: &Value) -> Result<Value> {
    let path = Path::new(text(v, "path")?);
    let output = Path::new(text(v, "output")?);
    if output.exists() && output.canonicalize()? == path.canonicalize()? {
        return Err("CAF input and catalogue output must differ".into());
    }
    let idx = caf::read_file(path)?;
    let root = idx.root_path.to_string_lossy().replace('\\', "/");
    staging(Path::new(text(v, "output")?), v["replace"] == true, |db| {
        create(db, &idx.root_path.to_string_lossy(), "caf_import")?;
        db.execute(
            "UPDATE meta SET header=?1",
            [serde_json::to_string(&idx.header)?],
        )?;
        let mut dirs = std::collections::HashSet::from([String::new()]);
        for (directory, mtime) in &idx.directories {
            let full = directory.to_string_lossy().replace('\\', "/");
            let prefix = format!("{}/", root.trim_end_matches('/'));
            let rel = if root.is_empty() {
                full.as_str()
            } else {
                full.strip_prefix(&prefix)
                    .ok_or("CAF directory outside root")?
            };
            let rel = relative(Path::new(rel))?;
            dirs.insert(rel.clone());
            db.execute(
                "INSERT INTO entries(path,parent,kind,depth,mtime) VALUES(?1,?2,1,?3,?4)",
                params![rel, parent(&rel), rel.split('/').count() as i64, *mtime],
            )?;
        }
        let unknown: std::collections::HashSet<_> = idx.unknown_size_paths.iter().collect();
        for entry in &idx.all_files {
            let full = entry.path.to_string_lossy().replace('\\', "/");
            let prefix = format!("{}/", root.trim_end_matches('/'));
            let rel = if root.is_empty() {
                full.as_str()
            } else {
                full.strip_prefix(&prefix)
                    .ok_or("CAF file is outside its root")?
            };
            let rel = relative(Path::new(rel))?;
            let parts: Vec<_> = rel.split('/').collect();
            for depth in 1..parts.len() {
                let dir = parts[..depth].join("/");
                if dirs.insert(dir.clone()) {
                    db.execute(
                        "INSERT INTO entries(path,parent,kind,depth) VALUES(?1,?2,1,?3)",
                        params![dir, parent(&dir), depth as i64],
                    )?;
                }
            }
            if entry.size > MAX_BYTES {
                return Err("CAF file exceeds exact byte-reporting bound".into());
            }
            db.execute("INSERT INTO entries(path,parent,kind,depth,bytes,files,mtime) VALUES(?1,?2,0,?3,?4,1,?5)",params![rel,parent(&rel),parts.len() as i64,if unknown.contains(&entry.path){0}else{entry.size as i64},entry.mtime])?;
        }
        for path in &idx.unknown_size_paths {
            let full = path.to_string_lossy().replace('\\', "/");
            let prefix = format!("{}/", root.trim_end_matches('/'));
            let rel = full.strip_prefix(&prefix).unwrap_or(&full);
            add_issue(db,rel,"legacy_unknown_size","Legacy CAF zero-size record does not establish exact size; excluded from known byte totals")?;
        }
        // CAF cannot establish source coverage or preserve our error history.
        add_issue(db,"","caf_coverage_unknown","CAF import is historical; source coverage, skipped links and scan errors are not encoded. Legacy v1-v6 zero-size file values are reported as unknown, not invented bytes.")?;
        db.execute("UPDATE meta SET visited=(SELECT count(*) FROM entries)", [])?;
        Ok(())
    })
}
fn query(v: &Value) -> Result<Value> {
    let db = open(text(v, "index")?)?;
    let sub = relative(Path::new(v["path"].as_str().unwrap_or("")))?;
    let top = number(v, "top", 20)?;
    if !(1..=10000).contains(&top) {
        return Err("top must be 1..10000".into());
    }
    let mut report = info(&db)?;
    let root = report["root"].as_str().unwrap().to_owned();
    let display = |rel: &str| {
        if rel.is_empty() {
            root.clone()
        } else {
            let windows = if report["origin"] == "caf_import" {
                root.contains('\\') || root.as_bytes().get(1) == Some(&b':')
            } else {
                cfg!(windows)
            };
            let separator = if windows { "\\" } else { "/" };
            format!(
                "{}{}{}",
                root.trim_end_matches(['/', '\\']),
                separator,
                if windows {
                    rel.replace('/', "\\")
                } else {
                    rel.to_owned()
                }
            )
        }
    };
    let node=db.query_row("SELECT bytes,files,dirs,complete,depth,kind FROM entries WHERE path=?1",[&sub],|r|Ok(json!({
        "path":display(&sub),"bytes":r.get::<_,i64>(0)?,"files":r.get::<_,i64>(1)?,"directories":r.get::<_,i64>(2)?,
        "complete":r.get::<_,bool>(3)?,"depth":r.get::<_,i64>(4)?,"type":if r.get::<_,i64>(5)?==1{"directory"}else{"file"}
    })))?;
    let files = v["filesOnly"] == true;
    let dirs = v["directoriesOnly"] == true;
    if files && dirs {
        return Err("Choose files or directories".into());
    }
    let recursive = v["recursive"] == true || files;
    let prefix = if sub.is_empty() {
        String::new()
    } else {
        format!("{sub}/")
    };
    let upper = format!("{prefix}\u{10ffff}");
    let search = v["search"].as_str().unwrap_or("");
    let mut conditions = vec!["path<>?1", "path>=?2", "path<?3"];
    if !recursive {
        conditions.push("parent=?1");
    }
    if files {
        conditions.push("kind=0");
    }
    if dirs {
        conditions.push("kind=1");
    }
    conditions.push("(?4='' OR instr(lower(path),lower(?4))>0)");
    let sql=format!("SELECT path,kind,bytes,files,dirs,complete,mtime FROM entries WHERE {} ORDER BY bytes DESC,path LIMIT ?5",conditions.join(" AND "));
    let mut stmt = db.prepare(&sql)?;
    let rows=stmt.query_map(params![sub,prefix,upper,search,top as i64],|r|{
      let path:String=r.get(0)?;
      Ok(json!({"path":display(&path),"relativePath":path,"type":if r.get::<_,i64>(1)?==1{"directory"}else{"file"},
        "bytes":r.get::<_,i64>(2)?,"files":r.get::<_,i64>(3)?,"directories":r.get::<_,i64>(4)?,"complete":r.get::<_,bool>(5)?,"mtimeUnix":r.get::<_,Option<i64>>(6)?}))
    })?.collect::<std::result::Result<Vec<_>,_>>()?;
    let mut issues = db.prepare("SELECT path,code,detail FROM issues")?;
    let issues=issues.query_map([],|r|Ok(json!({"path":r.get::<_,String>(0)?,"code":r.get::<_,String>(1)?,"detail":r.get::<_,String>(2)?})))?.collect::<std::result::Result<Vec<_>,_>>()?;
    report["catalogueTotals"] = json!({"bytes":report["bytes"],"files":report["files"],"directories":report["directories"]});
    for key in ["bytes", "files", "directories"] {
        report[key] = node[key].clone();
    }
    report["root"] = node;
    report["entries"] = json!(rows);
    report["issues"] = json!(issues);
    Ok(report)
}
fn export_caf(v: &Value) -> Result<Value> {
    let db = open(text(v, "index")?)?;
    let report = info(&db)?;
    let allow_loss = v["allowLossy"] == true;
    if !allow_loss && report["complete"] != true {
        return Err("CAF cannot retain completeness diagnostics; review --allow-lossy to export only observed files".into());
    }
    let unknown: i64 = db.query_row(
        "SELECT count(*) FROM issues WHERE code='legacy_unknown_size'",
        [],
        |r| r.get(0),
    )?;
    if unknown > 0 {
        return Err("Cannot export CAF entries with unknown sizes; retain the native catalogue or rescan the original source".into());
    }
    let output = Path::new(text(v, "output")?);
    let input = Path::new(text(v, "index")?).canonicalize()?;
    if output.exists() && output.canonicalize()? == input {
        return Err("CAF output must differ from catalogue database".into());
    }
    if output.exists() && v["replace"] != true {
        return Err("Output exists; use --replace".into());
    }
    let root = report["root"].as_str().unwrap();
    let mut idx = FileIndex::new(PathBuf::from(root), root.contains('\\'));
    let header: Option<String> =
        db.query_row("SELECT header FROM meta WHERE id=1", [], |r| r.get(0))?;
    if let Some(header) = header {
        idx.header = serde_json::from_str(&header)?;
    }
    let mut directories =
        db.prepare("SELECT path,mtime FROM entries WHERE kind=1 AND path<>'' ORDER BY path")?;
    let mut directory_rows = directories.query([])?;
    while let Some(row) = directory_rows.next()? {
        let path: String = row.get(0)?;
        let mtime: Option<i64> = row.get(1)?;
        let time = mtime
            .and_then(|x| u32::try_from(x).ok())
            .ok_or("CAF directory timestamp is unknown or outside its representable range")?;
        idx.directories.push((Path::new(root).join(path), time));
    }
    let mut stmt = db.prepare("SELECT path,bytes,mtime FROM entries WHERE kind=0 ORDER BY path")?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let path: String = row.get(0)?;
        let mtime: Option<i64> = row.get(2)?;
        let time = mtime
            .and_then(|x| u32::try_from(x).ok())
            .ok_or("CAF requires representable unsigned 32-bit timestamps; output unchanged")?;
        // No duplicate-finder buckets are needed for an export.
        idx.all_files.push(FileEntry::new(
            Path::new(root).join(path),
            u64::try_from(row.get::<_, i64>(1)?)?,
            time,
        ));
    }
    // The newer CrispSorter codec permits a UTF-8 extension. Classic Cathy
    // and the reviewed Python Catfish reader interpret Latin-1 only, so do
    // not silently emit that extension from our compatibility export.
    for value in std::iter::once(root)
        .chain([
            idx.header.label.as_str(),
            idx.header.alias.as_str(),
            idx.header.comment.as_str(),
        ])
        .chain(idx.all_files.iter().map(|e| e.path.to_str().unwrap_or("")))
        .chain(idx.directories.iter().map(|e| e.0.to_str().unwrap_or("")))
    {
        if value.chars().any(|c| c as u32 > 255) {
            return Err("Classic CAF requires Latin-1 names; use the Unicode-native .crispindex catalogue instead".into());
        }
    }
    let temp = tempfile::Builder::new().prefix(".crisp-caf-").tempfile_in(
        output
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or(Path::new(".")),
    )?;
    caf::write_file(temp.path(), &idx, u32::try_from(now())?)?;
    if v["replace"] == true {
        temp.persist(output).map_err(|e| e.error)?;
    } else {
        temp.persist_noclobber(output).map_err(|e| e.error)?;
    }
    Ok(
        json!({"output":text(v,"output")?,"version":8,"files":idx.len(),"lossy":report["complete"]!=true,
      "limitations":["Latin-1 names only","No completeness diagnostics","Second-resolution unsigned 32-bit timestamps"]}),
    )
}
pub fn execute(v: &Value) -> Result<Value> {
    match text(v, "op")? {
        "scan" => scan(v),
        "import" => import_caf(v),
        "query" => query(v),
        "info" => info(&open(text(v, "index")?)?),
        "export" => export_caf(v),
        _ => Err("Unknown catalogue operation".into()),
    }
}
/// C API owns the returned string until `crisp_catalog_free`. Requests are
/// bounded JSON; metadata rows stay in SQLite/Rust instead of crossing FFI.
#[no_mangle]
pub unsafe extern "C" fn crisp_catalog_call(request: *const c_char) -> *mut c_char {
    let response = std::panic::catch_unwind(|| {
        if request.is_null() {
            return json!({"error":"Null request"});
        }
        let bytes = CStr::from_ptr(request).to_bytes();
        if bytes.len() > 1024 * 1024 {
            return json!({"error":"Request exceeds 1 MiB"});
        }
        match serde_json::from_slice::<Value>(bytes)
            .map_err(|e| e.into())
            .and_then(|v| execute(&v))
        {
            Ok(value) => json!({"result":value}),
            Err(e) => json!({"error":e.to_string()}),
        }
    })
    .unwrap_or_else(|_| json!({"error":"Native catalogue operation failed"}));
    CString::new(response.to_string()).unwrap().into_raw()
}
#[no_mangle]
pub unsafe extern "C" fn crisp_catalog_free(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn scan_fixture() -> (tempfile::TempDir, PathBuf, PathBuf) {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("source");
        std::fs::create_dir_all(root.join("folder/empty")).unwrap();
        std::fs::write(root.join("a"), [0; 20]).unwrap();
        std::fs::write(root.join("folder/big"), [0; 50]).unwrap();
        let output = temp.path().join("volume.crispindex");
        (temp, root, output)
    }
    #[test]
    fn scan_aggregates_and_offline_queries() {
        let (_temp, root, output) = scan_fixture();
        let result = execute(&json!({"op":"scan","path":root,"output":output})).unwrap();
        assert_eq!(result["bytes"], 70);
        assert_eq!(result["files"], 2);
        assert_eq!(result["directories"], 2);
        assert_eq!(result["complete"], true);
        std::fs::remove_dir_all(&root).unwrap();
        let query = execute(&json!({"op":"query","index":output})).unwrap();
        assert_eq!(query["entries"][0]["bytes"], 50);
        assert_eq!(query["entries"][0]["type"], "directory");
        let files =
            execute(&json!({"op":"query","index":output,"filesOnly":true,"top":1})).unwrap();
        assert_eq!(files["entries"][0]["relativePath"], "folder/big");
        let sub = execute(&json!({"op":"query","index":output,"path":"folder"})).unwrap();
        assert_eq!(sub["root"]["bytes"], 50);
        assert_eq!(sub["entries"].as_array().unwrap().len(), 2);
    }
    #[test]
    fn partial_limits_and_existing_publication_are_explicit() {
        let (_temp, root, output) = scan_fixture();
        let first =
            execute(&json!({"op":"scan","path":root,"output":output,"maxEntries":1})).unwrap();
        assert_eq!(first["complete"], false);
        let previous = std::fs::read(&output).unwrap();
        assert!(execute(&json!({"op":"scan","path":root,"output":output})).is_err());
        assert!(execute(
            &json!({"op":"scan","path":root.join("missing"),"output":output,"replace":true})
        )
        .is_err());
        assert_eq!(std::fs::read(&output).unwrap(), previous);
        assert_eq!(
            execute(&json!({"op":"scan","path":root,"output":output,"replace":true})).unwrap()
                ["complete"],
            true
        );
    }
    #[test]
    fn caf_round_trip_preserves_empty_directories_and_warns_about_coverage() {
        let (temp, root, output) = scan_fixture();
        execute(&json!({"op":"scan","path":root,"output":output})).unwrap();
        let caf = temp.path().join("volume.caf");
        let exported =
            execute(&json!({"op":"export","index":output,"output":caf,"allowLossy":true})).unwrap();
        assert_eq!(exported["files"], 2);
        assert_eq!(exported["lossy"], false);
        let imported = temp.path().join("imported.crispindex");
        let imported = execute(&json!({"op":"import","path":caf,"output":imported})).unwrap();
        assert_eq!(imported["bytes"], 70);
        assert_eq!(imported["complete"], false);
        assert_eq!(imported["directories"], 2);
    }
    #[test]
    fn unicode_is_preserved_natively_and_caf_failure_preserves_output() {
        let (temp, root, output) = scan_fixture();
        std::fs::write(root.join("漢字.txt"), [0; 4]).unwrap();
        execute(&json!({"op":"scan","path":root,"output":output})).unwrap();
        let caf = temp.path().join("volume.caf");
        std::fs::write(&caf, b"previous").unwrap();
        let error = execute(
            &json!({"op":"export","index":output,"output":caf,"replace":true,"allowLossy":true}),
        )
        .unwrap_err();
        assert!(error.to_string().contains("Latin-1"));
        assert_eq!(std::fs::read(&caf).unwrap(), b"previous");
        let query = execute(&json!({"op":"query","index":output,"search":"漢字","recursive":true}))
            .unwrap();
        assert_eq!(query["entries"].as_array().unwrap().len(), 1);
    }
    #[test]
    fn malformed_import_does_not_replace_a_saved_index() {
        let (temp, root, output) = scan_fixture();
        execute(&json!({"op":"scan","path":root,"output":output})).unwrap();
        let old = std::fs::read(&output).unwrap();
        let caf = temp.path().join("bad.caf");
        std::fs::write(&caf, b"bad caf").unwrap();
        assert!(
            execute(&json!({"op":"import","path":caf,"output":output,"replace":true})).is_err()
        );
        assert_eq!(std::fs::read(&output).unwrap(), old);
        assert!(execute(&json!({"op":"query","index":output,"path":"../outside"})).is_err());
        let self_index = root.join("self.crispindex");
        let self_report = execute(&json!({"op":"scan","path":root,"output":self_index})).unwrap();
        assert_eq!(self_report["bytes"], 70);
        assert!(self_report["catalogueFilesSkipped"].as_i64().unwrap() > 0);
        let refreshed =
            execute(&json!({"op":"scan","path":root,"output":self_index,"replace":true})).unwrap();
        assert_eq!(refreshed["bytes"], 70);
    }
    #[cfg(unix)]
    #[test]
    fn symlinks_and_hardlinks_have_the_declared_semantics() {
        use std::os::unix::fs::symlink;
        let (_temp, root, output) = scan_fixture();
        symlink(&root, root.join("folder/loop")).unwrap();
        symlink(root.join("missing"), root.join("broken")).unwrap();
        std::fs::hard_link(root.join("a"), root.join("a2")).unwrap();
        let report = execute(&json!({"op":"scan","path":root,"output":output})).unwrap();
        assert_eq!(report["bytes"], 90);
        assert_eq!(report["linksSkipped"], 2);
        assert_eq!(report["complete"], true);
    }
}

#[cfg(test)]
mod volume_scale_test {
    use super::*;
    #[test]
    #[ignore = "explicit million-row SQLite scale qualification"]
    fn more_than_one_million_entries_remain_queryable() {
        let temp = tempfile::tempdir().unwrap();
        let output = temp.path().join("million.crispindex");
        let started = std::time::Instant::now();
        let count = 1_000_005i64;
        staging(&output,false,|db| {
            create(db,"/synthetic-volume","scale_test")?;
            let mut insert=db.prepare("INSERT INTO entries(path,parent,kind,depth,bytes,files,mtime) VALUES(?1,'',0,1,?2,1,1700000000)")?;
            for n in 0..count {insert.execute(params![format!("file-{n:07}"),n])?;}
            db.execute("UPDATE meta SET visited=?1",[count+1])?;
            Ok(())
        }).unwrap();
        let build_ms = started.elapsed().as_millis();
        let query_start = std::time::Instant::now();
        let result =
            execute(&json!({"op":"query","index":output,"filesOnly":true,"top":3})).unwrap();
        assert_eq!(result["root"]["files"], count);
        assert_eq!(result["root"]["bytes"], count * (count - 1) / 2);
        assert_eq!(result["entries"][0]["bytes"], count - 1);
        assert_eq!(result["entries"].as_array().unwrap().len(), 3);
        assert_eq!(result["complete"], true);
        println!(
            "synthetic_rows={count} build_ms={build_ms} query_ms={} database_bytes={}",
            query_start.elapsed().as_millis(),
            std::fs::metadata(output).unwrap().len()
        );
    }
}

#[cfg(test)]
mod caf_adaptation_tests {
    use super::*;
    #[test]
    fn legacy_zero_sizes_are_unknown_without_invented_bytes() {
        let temp = tempfile::tempdir().unwrap();
        let caf = temp.path().join("old.caf");
        let mut idx = FileIndex::new(PathBuf::from("/legacy"), false);
        idx.save_version = 6;
        idx.add(FileEntry::new(
            PathBuf::from("/legacy/unknown"),
            0,
            1700000000,
        ));
        idx.add(FileEntry::new(
            PathBuf::from("/legacy/known"),
            1024,
            1700000000,
        ));
        caf::write_file(&caf, &idx, 1700000000).unwrap();
        let output = temp.path().join("legacy.crispindex");
        let report = execute(&json!({"op":"import","path":caf,"output":output})).unwrap();
        assert_eq!(report["bytes"], 1024);
        let report = execute(&json!({"op":"query","index":output,"filesOnly":true})).unwrap();
        let rows = report["entries"].as_array().unwrap();
        assert_eq!(rows[0]["bytes"], 1024);
        assert_eq!(rows[1]["bytes"], 0);
        assert_eq!(rows[1]["complete"], false);
        assert!(execute(&json!({"op":"export","index":output,"output":temp.path().join("out.caf"),"allowLossy":true})).is_err());
    }
    #[test]
    fn caf_retains_empty_directory_and_directory_mtime_offline() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("empty.caf");
        let mut idx = FileIndex::new(PathBuf::from("/offline"), false);
        idx.directories
            .push((PathBuf::from("/offline/empty"), 1700000007));
        idx.directories
            .push((PathBuf::from("/offline/empty/nested"), 1700000009));
        caf::write_file(&path, &idx, 1700000000).unwrap();
        let mut loaded = caf::read_file(&path).unwrap().directories;
        loaded.sort();
        assert_eq!(loaded, idx.directories);
    }
}
