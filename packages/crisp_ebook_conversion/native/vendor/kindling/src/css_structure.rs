// CrispCloud local adaptation, MIT. A bounded structural check only. Property
// names, selector grammar and browser-specific CSS validity are not validated.
pub(crate) fn check(text: &str) -> Result<(), String> {
    let mut chars = text.chars().peekable();
    let mut stack = Vec::new();
    let mut quote = None;
    let mut pending = false;
    while let Some(c) = chars.next() {
        if let Some(q) = quote {
            if c == '\\' { chars.next(); }
            else if c == q { quote = None; }
            continue;
        }
        if c == '/' && chars.peek() == Some(&'*') {
            chars.next();
            let mut closed = false;
            while let Some(c) = chars.next() {
                if c == '*' && chars.peek() == Some(&'/') {
                    chars.next();
                    closed = true;
                    break;
                }
            }
            if !closed { return Err("Unclosed CSS comment.".into()); }
            continue;
        }
        if c == '\\' { chars.next(); continue; }
        if c == '"' || c == '\'' { quote = Some(c); continue; }
        match c {
            '{' | '(' | '[' => {
                if stack.len() >= 1024 { return Err("CSS nesting limit exceeded.".into()); }
                stack.push(c);
                pending = false;
            }
            '}' | ')' | ']' => {
                let expected = match c { '}' => '{', ')' => '(', _ => '[' };
                if stack.pop() != Some(expected) { return Err("Mismatched CSS delimiter.".into()); }
                if stack.is_empty() { pending = false; }
            }
            ';' if stack.is_empty() => pending = false,
            c if stack.is_empty() && !c.is_whitespace() => pending = true,
            _ => (),
        }
    }
    if quote.is_some() || !stack.is_empty() || pending {
        return Err("Unclosed CSS string or rule.".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn handles_comments_strings_and_delimiters() {
        assert!(check("/*{}*/ p { content: '}'; color: rgb(1,2,3); }").is_ok());
        assert!(check("p { color: red;").is_err());
        assert!(check("p { content: \"x; }").is_err());
        assert!(check("@media").is_err());
        assert!(check("/* no close").is_err());
    }
}
