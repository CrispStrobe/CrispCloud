#!/usr/bin/env python3
"""List likely hard-coded UI strings for manual localization review.

This deliberately reports candidates, not a coverage percentage: it misses
indirect and dynamically constructed text and may include non-linguistic text.
"""
from collections import Counter
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
PATTERN = re.compile(
    r"\b(?:Text|Tooltip)\s*\(\s*(?:const\s+)?[rR]?['\"]"
    r"|\b(?:labelText|hintText|helperText|errorText|semanticLabel|tooltip|"
    r"label|title|subtitle|message|description|confirmLabel|cancelLabel)"
    r"\s*:\s*[rR]?['\"]"
)


def main():
    counts = Counter()
    for path in (ROOT / 'lib').rglob('*.dart'):
        if path.parent.name == 'l10n':
            continue
        source = path.read_text(encoding='utf-8')
        for match in PATTERN.finditer(source):
            line = source.count('\n', 0, match.start()) + 1
            relative = path.relative_to(ROOT)
            counts[str(relative)] += 1
            print(f'{relative}:{line}: {source[match.start():].splitlines()[0].strip()}')
    print(f'\n{sum(counts.values())} candidate sites in {len(counts)} files; '
          'manual review required, and this is not a coverage percentage.')


if __name__ == '__main__':
    main()
