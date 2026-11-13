// Standalone audit adapter for the separately licensed crisp-docx executable.
// SPDX-License-Identifier: AGPL-3.0-or-later
// Authored for this audit; no crisp-docx implementation code is copied here.
use crisp_docx_core::{
    check_package, extract_paragraph_runs, extract_paragraph_texts, open,
    replace_paragraph_runs, replace_paragraph_texts, save, Package,
};
use serde_json::{json, Value};

fn paragraphs(package: &Package) -> Value {
    let texts = extract_paragraph_texts(package)
        .map(|value| json!(value))
        .unwrap_or_else(|error| json!({"error": error.to_string()}));
    let runs = extract_paragraph_runs(package)
        .map(|paragraphs| json!(paragraphs.iter().map(|p| json!({
            "text": p.full_text(),
            "pPr": p.ppr_xml.as_ref().map(|s| String::from_utf8_lossy(s).to_string()),
            "leadingBookmarks": p.leading_bookmark_starts.iter().map(|s| String::from_utf8_lossy(s).to_string()).collect::<Vec<_>>(),
            "trailingBookmarks": p.trailing_bookmark_ends.iter().map(|s| String::from_utf8_lossy(s).to_string()).collect::<Vec<_>>(),
            "runs": p.runs.iter().map(|r| json!({
                "text": r.text,
                "rPr": r.rpr_xml.as_ref().map(|s| String::from_utf8_lossy(s).to_string()),
                "footnotes": r.footnote_refs.iter().map(|s| String::from_utf8_lossy(s).to_string()).collect::<Vec<_>>(),
            })).collect::<Vec<_>>()
        })).collect::<Vec<_>>()))
        .unwrap_or_else(|error| json!({"error": error.to_string()}));
    json!({"texts": texts, "paragraphRuns": runs})
}

fn inspect(package: &Package) -> Value {
    let report = check_package(package)
        .map(|r| json!({"clean":r.is_clean(),"ok":r.ok,"issues":r.issues}))
        .unwrap_or_else(|e| json!({"error":e.to_string()}));
    let mut parts = Vec::new();
    for (name, bytes) in package.parts() {
        if name == "word/document.xml" || name == "word/footnotes.xml"
            || name == "word/endnotes.xml" || name == "word/comments.xml"
            || name.starts_with("word/header") && name.ends_with(".xml")
            || name.starts_with("word/footer") && name.ends_with(".xml") {
            // Calling the same public paragraph API with one selected part.
            // Part identity is adapter metadata; core does not supply story IDs.
            let mut view = Package::new();
            view.set_part("word/document.xml", bytes.to_vec());
            parts.push(json!({"part":name,"bytes":bytes.len(),"projection":paragraphs(&view)}));
        }
    }
    json!({"check":report,"publicBodyProjection":paragraphs(package),"perPartProjections":parts})
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().collect();
    if args.len() < 3 { return Err("usage: oracle_adapter inspect|runs|text|save INPUT [OUTPUT]".into()); }
    let mut package = open(&args[2])?;
    match args[1].as_str() {
        "inspect" => println!("{}", serde_json::to_string_pretty(&inspect(&package))?),
        "runs" => {
            let data = extract_paragraph_runs(&package)?;
            replace_paragraph_runs(&mut package, &data)?;
            save(&package, args.get(3).ok_or("missing output")?)?;
        }
        "text" => {
            let data = extract_paragraph_texts(&package)?;
            replace_paragraph_texts(&mut package, &data)?;
            save(&package, args.get(3).ok_or("missing output")?)?;
        }
        "save" => save(&package, args.get(3).ok_or("missing output")?)?,
        _ => return Err("unknown operation".into()),
    }
    Ok(())
}
