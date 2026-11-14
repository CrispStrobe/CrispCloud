//! Cooperative jobs. Only progress/cancellation crosses this table; no handles,
//! credentials or catalogue contents. Each long request removes its own state.
use super::Result;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
#[derive(Default)]
struct State {
    cancelled: bool,
    running: bool,
    progress: Value,
}
static JOBS: OnceLock<Mutex<HashMap<String, State>>> = OnceLock::new();
fn table() -> &'static Mutex<HashMap<String, State>> {
    JOBS.get_or_init(|| Mutex::new(HashMap::new()))
}
fn id(v: &Value) -> Option<&str> {
    v["jobId"].as_str().filter(|x| !x.is_empty())
}
pub fn begin(v: &Value) -> Result<()> {
    let Some(id) = id(v) else {
        return Ok(());
    };
    if id.len() > 128 {
        return Err("Job ID exceeds 128 bytes".into());
    }
    let mut jobs = table().lock().unwrap();
    if jobs.len() >= 64 && !jobs.contains_key(id) {
        return Err("Too many catalogue jobs".into());
    }
    let state = jobs.entry(id.to_owned()).or_default();
    if state.running {
        return Err("Job ID already running".into());
    }
    state.running = true;
    state.progress = json!({"phase":"starting"});
    Ok(())
}
pub fn check(v: &Value) -> Result<()> {
    if let Some(id) = id(v) {
        if table().lock().unwrap().get(id).is_some_and(|s| s.cancelled) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::Interrupted,
                "Catalogue operation stopped; unpublished output was discarded",
            )
            .into());
        }
    }
    Ok(())
}
pub fn cancelled(v: &Value) -> bool {
    check(v).is_err()
}
pub fn update(v: &Value, progress: Value) {
    if let Some(id) = id(v) {
        if let Some(state) = table().lock().unwrap().get_mut(id) {
            state.progress = progress;
        }
    }
}
pub fn finish(v: &Value) {
    if let Some(id) = id(v) {
        table().lock().unwrap().remove(id);
    }
}
pub fn cancel(v: &Value) -> Result<Value> {
    let id = id(v).ok_or("Missing jobId")?;
    if id.len() > 128 {
        return Err("Invalid jobId".into());
    }
    let mut jobs = table().lock().unwrap();
    if jobs.len() >= 64 && !jobs.contains_key(id) {
        return Err("Too many catalogue jobs".into());
    }
    jobs.entry(id.to_owned()).or_default().cancelled = true;
    Ok(json!({"stopRequested":true}))
}
pub fn status(v: &Value) -> Result<Value> {
    let id = id(v).ok_or("Missing jobId")?;
    Ok(table()
        .lock()
        .unwrap()
        .get(id)
        .map(|s| {
            let mut value = s.progress.clone();
            if !value.is_object() {
                value = json!({"phase":"starting"});
            }
            value["stopRequested"] = json!(s.cancelled);
            value
        })
        .unwrap_or_else(|| json!({"phase":"finished"})))
}
