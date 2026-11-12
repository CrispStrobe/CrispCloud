//! Remote path and name validation shared by both providers.
use crate::error::{CloudError, CloudResult, ErrorCode};

/// Split an absolute or relative remote path into validated components.
/// `""`, `"/"` and `"."` address the account root. `..` is rejected rather
/// than resolved so a caller cannot escape a confined path by accident.
pub fn components(path: &str) -> CloudResult<Vec<String>> {
    if path.contains('\0') {
        return Err(CloudError::new(ErrorCode::InvalidPath));
    }
    let mut result = Vec::new();
    for part in path.split('/') {
        match part {
            "" | "." => continue,
            ".." => return Err(CloudError::new(ErrorCode::InvalidPath)),
            other => result.push(other.to_owned()),
        }
    }
    Ok(result)
}

pub fn validate_name(name: &str) -> CloudResult<()> {
    if name.is_empty()
        || name == "."
        || name == ".."
        || name.contains('/')
        || name.contains('\\')
        || name.contains('\0')
        || name.len() > 1024
    {
        return Err(CloudError::new(ErrorCode::InvalidName));
    }
    Ok(())
}

/// Split a file name into Internxt's `plainName` and `type` fields.
/// Mirrors `package:path` basenameWithoutExtension/extension used by the Dart
/// adapter: a leading dot is part of the name, not an extension.
pub fn split_extension(name: &str) -> (&str, &str) {
    match name.rfind('.') {
        Some(0) | None => (name, ""),
        Some(index) if index + 1 == name.len() => (name, ""),
        Some(index) => (&name[..index], &name[index + 1..]),
    }
}

/// Small extension table for Filen's metadata `mime` field.
pub fn guess_mime(name: &str) -> &'static str {
    let (_, ext) = split_extension(name);
    match ext.to_ascii_lowercase().as_str() {
        "txt" | "log" | "md" => "text/plain",
        "html" | "htm" => "text/html",
        "css" => "text/css",
        "csv" => "text/csv",
        "json" => "application/json",
        "xml" => "application/xml",
        "pdf" => "application/pdf",
        "zip" => "application/zip",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        "mp3" => "audio/mpeg",
        "m4a" => "audio/mp4",
        "wav" => "audio/wav",
        "flac" => "audio/flac",
        "ogg" => "audio/ogg",
        "mp4" => "video/mp4",
        "mov" => "video/quicktime",
        "webm" => "video/webm",
        "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        _ => "application/octet-stream",
    }
}

/// True when `candidate` equals `ancestor` or lies below it.
pub fn is_same_or_descendant(candidate: &[String], ancestor: &[String]) -> bool {
    candidate.len() >= ancestor.len() && candidate[..ancestor.len()] == *ancestor
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn root_forms() {
        for root in ["", "/", ".", "//", "/./"] {
            assert!(components(root).unwrap().is_empty(), "{root}");
        }
    }

    #[test]
    fn normalizes_separators() {
        assert_eq!(components("/a//b/./c/").unwrap(), vec!["a", "b", "c"]);
        assert_eq!(components("a/b").unwrap(), vec!["a", "b"]);
        assert_eq!(components("/ä ö/💾").unwrap(), vec!["ä ö", "💾"]);
    }

    #[test]
    fn rejects_traversal_and_nul() {
        assert_eq!(components("/a/../b").unwrap_err().code, ErrorCode::InvalidPath);
        assert_eq!(components("..").unwrap_err().code, ErrorCode::InvalidPath);
        assert_eq!(components("/a\0b").unwrap_err().code, ErrorCode::InvalidPath);
    }

    #[test]
    fn names() {
        for ok in ["a", "a.txt", ".hidden", "ä b c", "..."] {
            validate_name(ok).unwrap();
        }
        for bad in ["", ".", "..", "a/b", "a\\b", "a\0"] {
            assert_eq!(validate_name(bad).unwrap_err().code, ErrorCode::InvalidName, "{bad:?}");
        }
        assert!(validate_name(&"x".repeat(1025)).is_err());
    }

    #[test]
    fn extensions() {
        assert_eq!(split_extension("a.txt"), ("a", "txt"));
        assert_eq!(split_extension("a.tar.gz"), ("a.tar", "gz"));
        assert_eq!(split_extension(".env"), (".env", ""));
        assert_eq!(split_extension("noext"), ("noext", ""));
        assert_eq!(split_extension("trailing."), ("trailing.", ""));
    }

    #[test]
    fn mime_table() {
        assert_eq!(guess_mime("A.PDF"), "application/pdf");
        assert_eq!(guess_mime("x.unknown"), "application/octet-stream");
        assert_eq!(guess_mime("noext"), "application/octet-stream");
        assert_eq!(guess_mime("song.mp3"), "audio/mpeg");
    }

    #[test]
    fn descendants() {
        let a = vec!["a".to_string()];
        let ab = vec!["a".to_string(), "b".to_string()];
        let other = vec!["ab".to_string()];
        assert!(is_same_or_descendant(&ab, &a));
        assert!(is_same_or_descendant(&a, &a));
        assert!(!is_same_or_descendant(&a, &ab));
        assert!(!is_same_or_descendant(&other, &a));
        assert!(is_same_or_descendant(&a, &[]));
    }
}
