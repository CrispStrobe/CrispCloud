use std::io::{self, Read};
use std::sync::atomic::AtomicBool;

fn main() {
    if std::env::args().nth(1).as_deref() == Some("--version") {
        println!("crisp-kindling 1 (Kindling 0.46.2)");
        return;
    }
    // A bounded JSON request on stdin, never a command line assembled from book
    // metadata. The same confinement and validation are used by the FFI path.
    let mut input = Vec::new();
    if io::stdin().take(131_073).read_to_end(&mut input).is_err() {
        std::process::exit(2);
    }
    let response = crisp_kindling_bridge::run_request_json(&input, &AtomicBool::new(false));
    println!("{response}");
}
