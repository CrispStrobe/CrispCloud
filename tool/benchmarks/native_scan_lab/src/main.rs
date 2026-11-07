use scanner_native_lab::{catalog_scan, serial_catalog, scan_tree, pack, Report};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64};
use std::time::Instant;
use serde_json::{json, Value};

fn median(v: &[f64]) -> f64 {
    let mut sorted = v.to_vec(); sorted.sort_by(f64::total_cmp); sorted[sorted.len()/2]
}
fn relative_path(path: &Path, root: &Path) -> String {
    path.strip_prefix(root).unwrap().components()
        .map(|c| c.as_os_str().to_str().unwrap()).collect::<Vec<_>>().join("/")
}
fn validate(report: &Report, root: &Path, expected: &Value) {
    assert!(report.root().complete, "{:?}", report.issues);
    assert_eq!(report.root().files as u64, expected["files"].as_u64().unwrap());
    assert_eq!(report.root().folders as u64, expected["foldersExcludingRoot"].as_u64().unwrap());
    assert_eq!(report.root().bytes, expected["logicalBytes"].as_u64().unwrap());
    let mut files: Vec<_> = report.nodes.iter().filter(|n| n.kind == 0)
        .map(|n| json!([relative_path(&n.path, root), n.size.unwrap(), n.mtime.unwrap()])).collect();
    files.sort_by(|a,b| a[0].as_str().cmp(&b[0].as_str()));
    assert_eq!(files, expected["records"].as_array().unwrap().to_vec());
    let mut directories: Vec<_> = report.nodes.iter().filter(|n| n.kind == 1)
        .map(|n| json!([relative_path(&n.path, root), n.mtime.unwrap()])).collect();
    directories.sort_by(|a,b| a[0].as_str().cmp(&b[0].as_str()));
    assert_eq!(directories, expected["directories"].as_array().unwrap().to_vec());
    for n in report.nodes.iter().filter(|n| n.kind == 1) {
        let path = relative_path(&n.path, root);
        assert_eq!(json!([n.bytes,n.files,n.folders]), expected["directoryTotals"][path]);
    }
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    assert!(args.len() >= 3, "usage: scanner-native-lab ROOT EXPECTED.json [REPS]");
    let root = Path::new(&args[1]);
    let expected: Value = serde_json::from_slice(&std::fs::read(&args[2]).unwrap()).unwrap();
    let reps: usize = args.get(3).map(|s| s.parse().unwrap()).unwrap_or(5);
    assert!(reps > 0);
    let cancel = AtomicBool::new(false);
    let progress = AtomicU64::new(0);
    for variant in ["catalog_jwalk_original", "catalog_serial_single_stat",
                    "tree_serial_single_stat", "tree_serial_strict", "tree_serial_strict_pack"] {
        let mut times = Vec::new();
        let mut payload_bytes = 0;
        for run in 0..=reps {
            let start = Instant::now();
            if variant.starts_with("catalog") {
                let index = if variant == "catalog_jwalk_original" {
                    catalog_scan::scan_dir(root, Default::default()).unwrap()
                } else { serial_catalog(root).unwrap() };
                let elapsed = start.elapsed().as_secs_f64() * 1000.0;
                if run != 0 { times.push(elapsed); }
                assert_eq!(index.len() as u64, expected["files"].as_u64().unwrap());
                assert_eq!(index.total_size(), expected["logicalBytes"].as_u64().unwrap());
                let mut records: Vec<_> = index.all_files.iter().map(|e|
                    json!([relative_path(&e.path, root),e.size,e.mtime])).collect();
                records.sort_by(|a,b| a[0].as_str().cmp(&b[0].as_str()));
                for (a,b) in records.iter().zip(expected["records"].as_array().unwrap()) {
                    assert_eq!(a[0], b[0]); assert_eq!(a[1], b[1]);
                    assert_eq!(a[2].as_u64().unwrap(), b[2].as_u64().unwrap()/1_000_000);
                }
                std::hint::black_box(index);
            } else {
                let strict = variant != "tree_serial_single_stat";
                let report = scan_tree(root, strict, &cancel, &progress);
                if variant.ends_with("_pack") {
                    let packed = pack(&report, 0).unwrap();
                    payload_bytes = packed.metrics[9];
                    std::hint::black_box(packed);
                }
                let elapsed = start.elapsed().as_secs_f64() * 1000.0;
                if run != 0 { times.push(elapsed); }
                validate(&report, root, &expected);
                std::hint::black_box(report);
            }
        }
        println!("{}", json!({"variant":variant,"medianMs":median(&times),
            "milliseconds":times,"warmups":1,"repetitions":reps,
            "files":expected["files"],"folders":expected["foldersExcludingRoot"],
            "logicalBytes":expected["logicalBytes"],"payloadBytes":payload_bytes,
            "allPathsSizesMtimesAndFolderTotalsValidated":!variant.starts_with("catalog"),
            "catalogTimestampResolutionSeconds":variant.starts_with("catalog"),
            "rayonThreads":rayon::current_num_threads()}));
    }
}
