"""Validate real Kindle -> Foliate -> crisp_ebook -> EPUBCheck fixture imports.

Run tool/smoke.py first to produce the reviewed original Kindle fixtures.
No input file is rewritten, and every input is hash-checked after the run.
The Node helper uses the reader's actual parser/security/normalization code;
the Dart helper uses the core's actual import, serialization and reopen APIs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = ROOT.parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command):
    subprocess.run([str(argument) for argument in command], check=True, cwd=ROOT)


def validate(epub, report, args):
    command = [args.java]
    if args.java_temp_dir:
        command.append(f"-Djava.io.tmpdir={args.java_temp_dir}")
    command.extend(["-jar", args.epubcheck, epub, "-j", report])
    run(command)
    result = json.loads(report.read_text(encoding="utf-8"))
    failures = [item for item in result["messages"]
                if item["severity"] in ("FATAL", "ERROR", "WARNING")]
    if failures:
        raise RuntimeError(f"EPUBCheck reported errors or warnings in {epub}: {failures}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--epubcheck", type=Path, required=True,
                        help="Path to the reviewed EPUBCheck 5.4.0 jar")
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--node", default="node")
    parser.add_argument("--java", default="java")
    parser.add_argument("--java-temp-dir", type=Path,
                        help="Optional writable Java ImageIO cache directory")
    parser.add_argument("--output", type=Path, default=ROOT / "build/import-chain")
    args = parser.parse_args()
    args.epubcheck = args.epubcheck.resolve(strict=True)
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.java_temp_dir:
        args.java_temp_dir = args.java_temp_dir.resolve()
        args.java_temp_dir.mkdir(parents=True, exist_ok=True)
    core_config = ROOT.parent / "crisp_ebook/.dart_tool/package_config.json"
    if not core_config.is_file():
        parser.error("Run dart pub get in packages/crisp_ebook first")
    sources = [ROOT / "test/fixtures/generated" / name
               for name in ("book.azw3", "book.mobi", "legacy.mobi")]
    source_epub = ROOT / "test/fixtures/book.epub"
    for source in [source_epub, *sources]:
        if not source.is_file():
            parser.error(f"Missing {source}; run tool/smoke.py first")
    baselines = {path: digest(path) for path in [source_epub, *sources]}
    try:
        validate(source_epub, args.output / "source.epubcheck.json", args)
        run([args.node, ROOT / "tool/normalize_import_fixture.mjs",
             REPOSITORY, args.output, *sources])
        run([args.dart, f"--packages={core_config}",
             ROOT / "tool/import_publication_fixture.dart", args.output])
        imports = json.loads((args.output / "import-results.json").read_text(encoding="utf-8"))
        if len(imports) != len(sources):
            raise RuntimeError("Expected exactly three real fixture imports")
        for item in imports:
            epub = Path(item["epub"])
            validate(epub, args.output / f"{epub.stem}.epubcheck.json", args)
    finally:
        for source, expected in baselines.items():
            if digest(source) != expected:
                raise RuntimeError(f"Source bytes changed: {source}")
    summary = {
        "sourceHashesPreserved": {str(path): value for path, value in baselines.items()},
        "imports": imports,
        "epubcheck": "Source EPUB and all three imported EPUBs: no errors or warnings",
    }
    (args.output / "verification.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(summary["epubcheck"])
    print("PASS actual Foliate -> normalized publication -> crisp_ebook import/reopen -> EPUBCheck")


if __name__ == "__main__":
    main()
