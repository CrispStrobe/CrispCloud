#!/usr/bin/env python3
"""Stage the exact production transport and its unchanged host test cases.

Run from the checkout's parent directory after preparing a pure Dart package
named quds_office_engine with the canonical Zotero core files under lib/src/zotero
and genuine http/test Pub dependencies:

    python zotero-core-validation/extract-host-transport.py

For other checkout layouts, set --crispcloud-root and --output. --check verifies
the staged source and test without rewriting them. No Dart statement in the
transport or selected test sections is altered; only test imports/main wrapper
exclude the unrelated Flutter controller and credential tests.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def section(source: str, start: str, end: str) -> str:
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError(f"Expected exactly one boundary: {start!r}, {end!r}")
    return source[source.index(start) : source.index(end)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--crispcloud-root", type=Path, default=Path("CrispCloud"))
    parser.add_argument(
        "--output", type=Path, default=Path("zotero-core-validation")
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    source = args.crispcloud_root / "lib/services/office_zotero_transport.dart"
    test_source = args.crispcloud_root / "test/office_zotero_test.dart"
    production = source.read_bytes()
    tests = test_source.read_bytes()
    text = tests.decode("utf-8")
    client = section(
        text,
        "class _Client extends http.BaseClient {",
        "class _Storage extends InMemorySecureStorage {",
    )
    helpers = section(text, "ZoteroHttpRequest _request(", "void main() {")
    group = section(
        text,
        "  group('Zotero transport boundary', () {",
        "  group('Zotero credential persistence', () {",
    )
    imports = (
        "import 'dart:async';\n"
        "import 'dart:convert';\n\n"
        "import 'package:http/http.dart' as http;\n"
        "import 'package:test/test.dart';\n"
        "import 'package:quds_office_engine/src/zotero/zotero_client.dart';\n"
        "import 'package:quds_office_engine/host_transport.dart';\n\n"
    )
    harness = (imports + client + helpers + "void main() {\n" + group + "}\n").encode(
        "utf-8"
    )
    staged_source = args.output / "lib/host_transport.dart"
    staged_tests = args.output / "test/host_transport_test.dart"
    receipt = {
        "scope": (
            "Exact unchanged production office_zotero_transport.dart compiled with its "
            "genuine http dependency and the canonical Zotero core client. The host test "
            "transport group, _Client class and request helpers are copied verbatim; "
            "imports use package:test and exclude unrelated Flutter controller and "
            "credential tests. This does not compile the host widget/provider graph or "
            "run native Flutter acceptance."
        ),
        "production_source": str(source),
        "production_sha256": sha256(production),
        "staged_source_sha256": sha256(production),
        "test_source": str(test_source),
        "test_source_sha256": sha256(tests),
        "test_harness_sha256": sha256(harness),
        "verbatim_test_sections": {
            "client_sha256": sha256(client.encode("utf-8")),
            "request_helpers_sha256": sha256(helpers.encode("utf-8")),
            "transport_group_sha256": sha256(group.encode("utf-8")),
        },
    }
    if args.check:
        if staged_source.read_bytes() != production:
            raise SystemExit("Staged production transport differs from canonical source")
        if staged_tests.read_bytes() != harness:
            raise SystemExit("Staged host test harness differs from verbatim extraction")
    else:
        staged_source.parent.mkdir(parents=True, exist_ok=True)
        staged_tests.parent.mkdir(parents=True, exist_ok=True)
        staged_source.write_bytes(production)
        staged_tests.write_bytes(harness)
        (args.output / "host-transport-extraction.json").write_text(
            json.dumps(receipt, indent=2) + "\n", encoding="utf-8"
        )
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
