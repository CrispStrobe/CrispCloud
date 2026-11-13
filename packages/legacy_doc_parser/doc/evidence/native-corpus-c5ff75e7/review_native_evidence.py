#!/usr/bin/env python3
"""Verify native source/receipt bindings and reproduce the retained comparison.

Never executes Office, Dart, or any captured source. The inherited comparison
helper uses assertions, so optimized Python is explicitly refused.
"""
import argparse
import copy
import hashlib
import importlib.util
import io
import json
import lzma
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile
import zipfile

if not __debug__:
    raise SystemExit("Run without Python optimization: comparison checks use assertions")

import compare_native_corpus as comparison

COMMIT = "c5ff75e76163d9abbdd44a9f2a7c5ad210929289"
TREE = "25bd05c12fa2272a32ec2aaba2cc0117be5bed96"
WORKSPACE = "/workspace/scratch/c1ca2a1344e9"
DART = WORKSPACE + "/toolchains/dart-3.13.7/dart-sdk/bin/dart"


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def check_bundle(root):
    record = json.loads((root / "bundle-files.json").read_bytes())
    require(record["sourceCommit"] == COMMIT and record["sourceTree"] == TREE, "Bundle identity")
    actual = [{"path": p.relative_to(root).as_posix(), "size": p.stat().st_size,
               "sha256": sha(p.read_bytes())} for p in sorted(root.rglob("*"))
              if p.is_file() and "__pycache__" not in p.relative_to(root).parts and
              p != root / "bundle-files.json"]
    require(record["files"] == actual, "Bundle file inventory/bytes differ: " + root.name)


def unpack_sources(root):
    manifest = json.loads((root / "source.manifest.json").read_bytes())
    require(manifest["sourceCommit"] == COMMIT and manifest["sourceTree"] == TREE,
            "Native source identity")
    record = manifest["archive"]
    require(record["path"] == "native-source.tar.xz", "Native source archive path")
    raw = (root / record["path"]).read_bytes()
    require(len(raw) == record["size"] and sha(raw) == record["sha256"], "Native source archive hash")
    expected = {entry["path"]: entry for entry in manifest["files"]}
    require(len(expected) == len(manifest["files"]) == 150, "Native source inventory")
    result = {}
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:xz") as archive:
        for member in archive:
            require(member.isfile() and member.name in expected and member.name not in result,
                    "Native source member inventory")
            data = archive.extractfile(member).read()
            require(expected[member.name] == {"path": member.name, "size": len(data), "sha256": sha(data)},
                    "Native source member bytes: " + member.name)
            result[member.name] = data
    require(set(result) == set(expected), "Missing native source")
    require(sha(canonical({name: sha(data) for name, data in result.items()})) == manifest["aggregateSha256"],
            "Native source aggregate")
    return result


def render_metrics(reference, actual):
    a, b = reference["pages"], actual["pages"]
    same_text = len(a) == len(b) and all(
        [w["text"] for w in x["words"]] == [w["text"] for w in y["words"]]
        for x, y in zip(a, b))
    drift = max([0.0] + [abs(x - y) for p, q in zip(a, b)
                for u, v in zip(p["words"], q["words"])
                for x, y in zip(u["box"], v["box"])]) if same_text else None
    sizes = len(a) == len(b) and all(x["size"] == y["size"] for x, y in zip(a, b))
    settings = (reference["rasterColorSpace"] == "RGB" and reference["rasterDpi"] > 0 and
                all(reference[k] == actual[k] for k in ("rasterDpi", "rasterColorSpace")))
    pixels = settings and reference["rasterSha256"] == actual["rasterSha256"]
    text = reference["text"] == actual["text"]
    return {"referencePages": len(a), "actualPages": len(b), "pageDimensionsMatch": sizes,
            "pageTextMatches": same_text, "maximumWordDriftPoints": drift, "tolerancePoints": 0.25,
            "matchesWithinTolerance": sizes and same_text and drift is not None and drift <= 0.25,
            "rasterSettingsMatch": settings, "rasterExactlyMatches": pixels,
            "layoutTextExactlyMatches": text,
            "exactOnThisRenderer": pixels and text and drift == 0 and sizes}


def check_report(report, sources, manifest, sidecars):
    require(report["parserCommit"] == manifest["sourceCommit"] == COMMIT and
            report["parserWorktreeDirty"] is manifest["sourceWorktreeDirty"] is False and
            report["status"] == "measured" and report["roundtripCyclesRequested"] == 3,
            "Native report completion/source identity")
    build = report["build"]
    hashes = {name: sha(data) for name, data in sources.items()}
    require(build["sources"]["files"] == hashes and build["sources"]["sha256"] == sha(canonical(hashes)) and
            build["sourcesUnchangedDuringCompilation"] is True, "Native build source binding")
    require(build["compileCommand"] == [DART, "compile", "exe", "tool/fidelity/convert.dart", "-o",
            WORKSPACE + "/final-native-c5ff75e7/convert"], "Native compile command")
    corpus = json.loads(sources["tool/fidelity/corpus.json"])
    require(report["corpusSha256"] == sha(sources["tool/fidelity/corpus.json"]), "Native corpus identity")
    require([case["id"] for case in report["cases"]] == [case["id"] for case in corpus["cases"]] and
            len(report["cases"]) == 24, "Native case inventory")
    require(all(stage["status"] == "complete" for stage in report["stages"]), "Incomplete global stage")
    entries = {entry["path"]: entry for entry in manifest["files"]}
    document_hashes = {entry["sha256"] for entry in manifest["files"] if entry["path"].endswith((".doc", ".docx"))}
    recomputed = 0
    for case, source in zip(report["cases"], corpus["cases"], strict=True):
        label = case["id"]
        require(case["status"] == "measured" and case["sourceUnchanged"] is True and
                case["binaryDocUnchanged"] is True and case["sourceSha256"] == source["sha256"] and
                entries["inputs/" + label + PurePosixPath(source["path"]).suffix]["sha256"] == source["sha256"],
                "Native case/source completion: " + label)
        require(all(stage["status"] == "complete" for stage in case["stages"]), "Incomplete case stage")
        renders = {}
        for kind in ("renders", "snapshots"):
            for name, ref in case[kind].items():
                path = "run/" + label + "/" + ref["path"]
                require(entries[path]["sha256"] == ref["sha256"] == sha(sidecars[path]) and
                        ref["documentSha256"] in document_hashes, "Native sidecar/document binding: " + path)
                if kind == "renders":
                    renders[name] = json.loads(sidecars[path])
                    require(renders[name]["rasterDpi"] == 72 and renders[name]["rasterColorSpace"] == "RGB",
                            "Native rendering settings")
        for name, key in (("binary", "binaryDocSha256"), ("converted", "convertedSha256"),
                          ("native", "nativeDocxSha256")):
            require(case["renders"][name]["documentSha256"] == case[key], "Native document identity")
        pairs = [("pagination", "binary", "converted"), ("nativeConversionPagination", "binary", "native")]
        if case["sourceFormat"] == "docx":
            pairs.append(("bridgePagination", "original", "binary"))
        for key, left, right in pairs:
            require(case[key] == render_metrics(renders[left], renders[right]), "Native metric derivation: " + label + "/" + key)
            recomputed += 1
        require(len(case["roundtripCycles"]) == case["roundtripCyclesRequested"] == 3, "Native cycle inventory")
        previous = "converted"
        for n, cycle in enumerate(case["roundtripCycles"], 1):
            prefix = f"roundtrip-{n:02d}-"
            require(cycle["index"] == n and cycle["status"] == "measured" and
                    cycle["inputUnchanged"] is True and cycle["binaryDocUnchanged"] is True,
                    "Native cycle completion")
            require(cycle["inputSha256"] == case["renders"][previous]["documentSha256"] and
                    cycle["binaryDocSha256"] == case["renders"][prefix + "binary"]["documentSha256"] and
                    cycle["convertedSha256"] == case["renders"][prefix + "converted"]["documentSha256"],
                    "Native cycle document chain")
            for key, left in (("paginationFromBinaryDoc", prefix + "binary"),
                              ("paginationFromPreviousImport", previous),
                              ("paginationFromFirstImport", "converted")):
                require(cycle[key] == render_metrics(renders[left], renders[prefix + "converted"]),
                        "Native cycle metric derivation: " + label + "/" + key)
                recomputed += 1
            previous = prefix + "converted"
    require(recomputed == 278, "Native metric coverage")
    return recomputed


def normalize_paths(value):
    result = copy.deepcopy(value)
    # Only the review helper's current input locations vary between checkouts.
    # Original tool paths and every other recorded field remain bound.
    for side in ("before", "after"):
        result[side].pop("input")
        for receipt in result[side]["receipts"]:
            receipt.pop("path")
    return result


def check_launch(root, portable_inputs, report, launch=None):
    if launch is None:
        launch = json.loads((root / "launch/native.launch.json").read_bytes())
    command = ["/opt/codex/runtimes/codex-primary-runtime/dependencies/python/bin/python3",
               "tool/fidelity/run.py", "--office",
               "/opt/codex/runtimes/codex-primary-runtime/dependencies/bin/override/soffice",
               "--dart", DART, "--output", WORKSPACE + "/final-native-c5ff75e7", "--dpi", "72",
               "--raster-storage", "gzip", "--roundtrip-cycles", "3"]
    require(launch["command"] == command and launch["cwd"] == WORKSPACE + "/parser-combined-next" and
            launch["gate"] == "native" and launch["status"] == "complete" and launch["exitCode"] == 0 and
            launch["success"] is True and launch["inputsUnchanged"] is True, "Native launch command/completion")
    require(launch["sourceBefore"] == launch["sourceAfter"] ==
            {"commit": COMMIT, "tree": TREE, "status": "", "files": portable_inputs}, "Native full input inventories")
    require(launch["environmentOverrides"] == {"DART_SUPPRESS_ANALYTICS": "true",
            "PUB_CACHE": WORKSPACE + "/toolchains/pub-cache", "TMPDIR": WORKSPACE + "/tmp"}, "Native launch environment")
    require(launch["launcherSha256"] == sha((root / "launch/run_final_acceptance_gate.py").read_bytes()) and
            launch["driverSourceSha256"] == portable_inputs["tool/fidelity/run.py"] and
            launch["consoleLog"] == "native.console.log" and
            launch["consoleSha256"] == sha((root / "launch/native.console.log").read_bytes()), "Native launcher/driver/log bytes")
    expected_lines = []
    for case in report["cases"]:
        bridge = case["bridgePagination"]["exactOnThisRenderer"] if case["sourceFormat"] == "docx" else "not-applicable"
        page = case["pagination"]
        expected_lines.append(f'{case["id"]}: measured; original-to-binary exact={bridge}; parser pages '
                              f'{page["referencePages"]} -> {page["actualPages"]}; parser exact={page["exactOnThisRenderer"]}')
    require((root / "launch/native.console.log").read_text().splitlines() == expected_lines,
            "Native console/report correspondence")
    return launch


def check_word14(root, controls=False):
    spec = importlib.util.spec_from_file_location("word14_pixels", root / "measure_word14_pixels.py")
    measure = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(measure)
    retained = json.loads((root / "word14-pixels.json").read_bytes())
    require(retained["schemaVersion"] == 1 and retained["dpi"] == 72 and
            retained["regions"] == measure.REGIONS and retained["method"] == measure.__doc__ and
            retained["helperSha256"] == sha((root / "measure_word14_pixels.py").read_bytes()), "Pixel review helper/method")
    names = ["binary", "converted"] + [f"roundtrip-{n:02d}-{kind}" for n in range(1, 4) for kind in ("binary", "converted")]
    wanted = {name + "-render.json" for name in names} | {
        "render-" + name + "/" + child for name in names for child in ("page-0001.ppm.gz", "raster-manifest.json")}
    payloads = {}
    for label, folder in (("before", root.parent / "native-corpus-74420eb2/sealed"), ("after", root / "sealed")):
        entries = {e["path"]: e for e in json.loads((folder / "native-artifacts.manifest.json").read_bytes())["files"]}
        with tarfile.open(folder / "native-artifacts.tar.xz", "r|xz") as archive:
            for member in archive:
                prefix = "run/word14-margin-origin/"
                if member.name.startswith(prefix) and member.name[len(prefix):] in wanted:
                    data = archive.extractfile(member).read()
                    entry = entries[member.name]
                    require(entry["sha256"] == sha(data) and entry["bytes"] == len(data), "Pixel review original artifact bytes")
                    payloads[label + "/" + member.name[len(prefix):]] = data
    require(set(payloads) == {side + "/" + path for side in ("before", "after") for path in wanted}, "Pixel review artifact coverage")
    derived = {}
    read = lambda path: payloads[path.as_posix()]
    for label in ("before", "after"):
        folder = Path(label)
        derived[label + "-initial-binary-vs-converted"] = measure.compare(folder, "binary", folder, "converted", read)
        for n in range(1, 4):
            prefix = f"roundtrip-{n:02d}"
            derived[label + "-" + prefix + "-binary-vs-converted"] = measure.compare(folder, prefix + "-binary", folder, prefix + "-converted", read)
    for name in names:
        derived["before-vs-after-" + name] = measure.compare(Path("before"), name, Path("after"), name, read)

    def normalized(value):
        result = copy.deepcopy(value)
        for pair in result.values():
            for side in ("reference", "actual"):
                pair[side].pop("receiptPath")
                pair[side].pop("rasterPath")
        return result

    def compare_record(value):
        require(normalized(value) == normalized(derived), "Retained Word14 pixel derivation")

    compare_record(retained["comparisons"])
    rejected = 0
    if controls:
        for field in ("changedPixels", "absoluteChannelDeltaSum"):
            changed = copy.deepcopy(retained["comparisons"])
            changed["after-roundtrip-01-binary-vs-converted"]["regions"]["texture_1026"][field] += 1
            try:
                compare_record(changed)
            except ValueError:
                rejected += 1
            else:
                raise ValueError("Accepted pixel summary corruption: " + field)
    return len(derived), rejected


def check_word14_source(root, controls=False):
    receipt = json.loads((root / "word14-source-triage.manifest.json").read_bytes())
    require(receipt["sourceCommit"] == COMMIT and receipt["baselineCommit"] ==
            "74420eb2e0ec14401a0db5bcbb30ab6d202a2340", "Word14 source review identities")
    archive_record = receipt["archive"]
    require(archive_record["path"] == "word14-source-triage.tar.xz", "Word14 source archive path")
    raw = (root / archive_record["path"]).read_bytes()
    require(len(raw) == archive_record["size"] and sha(raw) == archive_record["sha256"], "Word14 source archive bytes")
    expected = {e["path"]: e for e in receipt["files"]}
    require(set(expected) == {"README.md", "primary-sources.json", "review-manifest.json",
                              "word14-source-paint.json", "inspect_word14.py"} and len(receipt["files"]) == 5,
            "Word14 source file inventory")
    payloads = {}
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:xz") as archive:
        for member in archive:
            require(member.isfile() and member.name in expected and member.name not in payloads, "Word14 source archive members")
            data = archive.extractfile(member).read()
            require(expected[member.name] == {"path": member.name, "size": len(data), "sha256": sha(data)}, "Word14 source member bytes")
            payloads[member.name] = data
    require(set(payloads) == set(expected), "Missing Word14 source record")
    review = json.loads(payloads["review-manifest.json"])
    require(review["afterCommit"] == COMMIT and review["afterTree"] == TREE and
            review["beforeCommit"] == receipt["baselineCommit"] and review["nativeRerun"] is False and
            review["runtimeChangeJustifiedByThisReview"] is False and review["sourcePaintPackagesVerified"] == 14,
            "Word14 source review scope")
    require(review["files"] == {name: {"bytes": len(data), "sha256": sha(data)}
                                  for name, data in payloads.items() if name != "review-manifest.json"},
            "Word14 source internal inventory")
    require(review["externalPixelEvidence"] == {name: {"bytes": (root / local).stat().st_size,
            "sha256": sha((root / local).read_bytes())} for name, local in
            (("measure_word14_pixels.py", "measure_word14_pixels.py"),
             ("word14-pixels-c5ff75e7.json", "word14-pixels.json"))}, "Word14 source/pixel review binding")
    paint = json.loads(payloads["word14-source-paint.json"])
    require(paint["scriptSha256"] == sha(payloads["inspect_word14.py"]), "Word14 source inspector identity")
    paths = ["converted.docx"]
    for cycle in range(1, 4):
        paths += [f"roundtrip-{cycle:02}/import.docx", f"roundtrip-{cycle:02}/native-docx/" +
                  ("converted.docx" if cycle == 1 else "import.docx")]
    documents = {}
    for label, folder in (("before", root.parent / "native-corpus-74420eb2/sealed"), ("after", root / "sealed")):
        entries = {e["path"]: e for e in json.loads((folder / "native-artifacts.manifest.json").read_bytes())["files"]}
        with tarfile.open(folder / "native-artifacts.tar.xz", "r|xz") as archive:
            for member in archive:
                prefix = "run/word14-margin-origin/"
                if member.name.startswith(prefix) and member.name[len(prefix):] in paths + ["source.doc"]:
                    data = archive.extractfile(member).read()
                    require(entries[member.name]["sha256"] == sha(data) and entries[member.name]["bytes"] == len(data),
                            "Word14 source original package bytes")
                    documents[label + "/" + member.name[len(prefix):]] = data
    require(set(documents) == {side + "/" + path for side in ("before", "after") for path in paths + ["source.doc"]},
            "Word14 source package coverage")

    def identity(data):
        return {"bytes": len(data), "sha256": sha(data)}

    def validate_records(value):
        require(set(value["runs"]) == {"before", "after"}, "Word14 source run inventory")
        for label, run_root in (("before", WORKSPACE + "/parser-native-74420eb"),
                                ("after", WORKSPACE + "/final-native-c5ff75e7")):
            rows = value["runs"][label]
            require(len(rows) == len(paths) == 7 and rows[0]["binarySource"] == identity(documents[label + "/source.doc"]),
                    "Word14 source binary identity")
            for row, path in zip(rows, paths, strict=True):
                data = documents[label + "/" + path]
                require(row["path"] == run_root + "/word14-margin-origin/" + path and
                        {k: row[k] for k in ("bytes", "sha256")} == identity(data), "Word14 source package/report binding")
                with zipfile.ZipFile(io.BytesIO(data)) as package:
                    require(set(row["images"]) == {name for name in package.namelist() if name.startswith("word/media/")},
                            "Word14 source image inventory")
                    for name, item in row["images"].items():
                        require({k: item[k] for k in ("bytes", "sha256")} == identity(package.read(name)),
                                "Word14 source image bytes")
                    if "word/evidence/manifest.json" in package.namelist():
                        evidence = json.loads(package.read("word/evidence/manifest.json"))
                        artifacts = [e for e in evidence["records"] if e["kind"] == "officeArt"]
                        content = [e for e in artifacts if e["source"]["structure"] == "OfficeArtContent"]
                        require(len(content) == 1 and row["officeArt"]["source"] == identity(package.read(content[0]["part"])) and
                                row["officeArt"]["sourceReference"] == content[0]["source"], "Word14 source OfficeArt bytes")
                        blips = [e for e in artifacts if e["source"]["structure"] == "OfficeArtBlip"]
                        require(len(blips) == len(row["retainedBlips"]), "Word14 source BLIP inventory")
                        for recorded, entry in zip(row["retainedBlips"], blips, strict=True):
                            blip = package.read(entry["part"])
                            require(recorded["source"] == entry["source"] and recorded["record"] == identity(blip) and
                                    recorded["payload"] == identity(blip[25:]), "Word14 source BLIP/payload bytes")
                    else:
                        require("officeArt" not in row, "Unexpected native bridge source report")
        require(value["runs"]["before"][0]["binarySource"] == value["runs"]["after"][0]["binarySource"],
                "Word14 original binary identity differs")

    validate_records(paint)
    rejected = 0
    if controls:
        for location in ("package", "image"):
            corrupt = copy.deepcopy(paint)
            row = corrupt["runs"]["after"][1]
            target = row if location == "package" else next(iter(row["images"].values()))
            target["sha256"] = "0" * 64
            try:
                validate_records(corrupt)
            except ValueError:
                rejected += 1
            else:
                raise ValueError("Accepted Word14 source contradiction: " + location)
    return 14, rejected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--repository", type=Path)
    args = parser.parse_args()
    root = args.directory.resolve()
    check_bundle(root)
    artifact_check = json.loads(subprocess.check_output([sys.executable, str(root / "verify_native_artifacts.py"),
                                  "--directory", str(root / "sealed")]))
    manifest = json.loads((root / "sealed/native-artifacts.manifest.json").read_bytes())
    sources = unpack_sources(root)
    portable_root = root.parent / "continuation-c5ff75e7"
    check_bundle(portable_root)
    peer = json.loads((portable_root / "independent-review.json").read_bytes())
    portable_verification = json.loads((portable_root / "verification.json").read_bytes())
    peer_counts = {key: value for key, value in portable_verification.items()
                   if key not in {"archiveBytes", "archiveSha256", "parserCommit", "parserTree"}}
    require(peer["parserCommit"] == COMMIT and peer["parserTree"] == TREE and
            peer["bothCommandsObserved"] == peer_counts,
            "Independent portable review result/source binding")
    for name, record in peer["files"].items():
        path = "independent-reviewed-bundle-files.json" if name == "bundle-files.json" else name
        data = (portable_root / path).read_bytes()
        require(record == {"bytes": len(data), "sha256": sha(data)}, "Independent reviewed file bytes: " + name)
    expected_peer_commands = [["python3", *flags, "doc/evidence/continuation-c5ff75e7/seal_validation_evidence.py",
                               "--repository", ".", "--self-test"] for flags in ([], ["-O"])]
    require(peer["executedVerification"] == [{"command": command, "cwd": WORKSPACE + "/parser-final-evidence", "exitCode": 0}
                                            for command in expected_peer_commands], "Independent review commands")
    hosted = json.loads((portable_root / "hosted-ci.json").read_bytes())
    require(hosted["run"]["head_sha"] == COMMIT and hosted["run"]["id"] == 43387392944 and
            hosted["run"]["status"] == "completed" and hosted["run"]["conclusion"] == "success",
            "Hosted status source/result identity")
    jobs = hosted["jobs"]["jobs"]
    require({job["name"] for job in jobs} == {"test", "openxml-schema"} and len(jobs) == 2 and
            all(job["status"] == "completed" and job["conclusion"] == "success" and
                job["run_id"] == 43387392944 for job in jobs), "Hosted job status binding")
    hosted_spec = importlib.util.spec_from_file_location("hosted_ci", portable_root / "verify_hosted_ci.py")
    hosted_helper = importlib.util.module_from_spec(hosted_spec)
    hosted_spec.loader.exec_module(hosted_helper)
    hosted_result = hosted_helper.verify(portable_root, args.self_test)
    spec = importlib.util.spec_from_file_location("portable_seal", portable_root / "seal_validation_evidence.py")
    portable_helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(portable_helper)
    portable_manifest, portable_payloads = portable_helper.load_archive(portable_root)
    portable_helper.verify_payloads(portable_manifest, portable_payloads)
    portable_inputs = json.loads(portable_payloads["portable/receipt.json"])["inputsBefore"]
    require(all(portable_inputs[name] == sha(data) for name, data in sources.items()),
            "Native sources differ from portable acceptance")
    if args.repository:
        portable_helper.verify_repository(args.repository, portable_payloads)
    report, raw_hash = comparison.read_report(root / "sealed/native-report.json.xz", manifest["report"])
    wanted = {"run/" + case["id"] + "/" + ref["path"] for case in report["cases"]
              for kind in ("renders", "snapshots") for ref in case[kind].values()}
    sidecars = {}
    with tarfile.open(root / "sealed/native-artifacts.tar.xz", "r|xz") as archive:
        for member in archive:
            if member.name in wanted:
                sidecars[member.name] = archive.extractfile(member).read()
    require(set(sidecars) == wanted, "Missing native sidecars")
    count = check_report(report, sources, manifest, sidecars)
    launch = check_launch(root, portable_inputs, report)
    schema = json.loads(portable_payloads["schema/report.json"])
    require(report["build"]["compiler"]["sha256"] == schema["dart"]["executableSha256"] and
            report["build"]["compiler"]["version"] == schema["dart"]["version"],
            "Native and portable Dart binary identities differ")
    rejected = 0
    if args.self_test:
        # Mutate only targeted fields, restore each, and bypass outer checksums
        # deliberately so these controls reach semantic evidence bindings.
        fields = [(report, "parserWorktreeDirty", True), (report, "parserCommit", "0" * 40),
                  (report["build"], "compileCommand", ["true"]),
                  (report["build"], "sourcesUnchangedDuringCompilation", False),
                  (report["cases"][0], "status", "failed"),
                  (report["cases"][0]["pagination"], "exactOnThisRenderer", True),
                  (report["cases"][0]["roundtripCycles"][0], "inputSha256", "0" * 64),
                  (report["cases"][0]["roundtripCycles"][0]["paginationFromFirstImport"], "actualPages", 999),
                  (report["cases"][0]["renders"]["converted"], "sha256", "0" * 64)]
        for target, key, value in fields:
            old = target[key]
            require(old != value, "Nondiscriminating native corruption control")
            target[key] = value
            try:
                try:
                    check_report(report, sources, manifest, sidecars)
                except (ValueError, KeyError):
                    rejected += 1
                else:
                    raise ValueError("Accepted native corruption: " + key)
            finally:
                target[key] = old
        for key, value in (("command", ["true"]), ("sourceAfter", {}), ("consoleSha256", "0" * 64)):
            corrupted = copy.deepcopy(launch)
            corrupted[key] = value
            try:
                check_launch(root, portable_inputs, report, corrupted)
            except (ValueError, KeyError):
                rejected += 1
            else:
                raise ValueError("Accepted native launch corruption: " + key)
    del report, sidecars
    before = comparison.load_dataset(root.parent / "native-corpus-74420eb2/sealed")
    after = comparison.load_dataset(root / "sealed")
    require(after["environment"]["parserCommit"] == COMMIT, "Comparison source identity")
    derived = comparison.compare(before, after)
    retained = json.loads(lzma.decompress((root / "comparison-vs-74420eb2.json.xz").read_bytes()))
    require(normalize_paths(derived) == normalize_paths(retained), "Retained comparison differs from original reports")
    summary = json.loads((root / "summary.json").read_bytes())
    for key in ("cases", "cycles", "executionErrors", "initial", "bridge", "repeats", "sourceGoldenStatuses",
                "parserAgainstSourceGoldenStatuses", "strictInitialMatches", "allInputsUnchanged", "artifactCountsFromManifests"):
        require(summary[key] == derived["after"][key], "Summary binding: " + key)
    require(summary["sourceCommit"] == COMMIT and summary["sourceTree"] == TREE and
            summary["baselineComparisonContext"] == derived["context"], "Summary identity/context binding")
    require(summary["environment"] == {k: after["environment"][k] for k in summary["environment"]},
            "Summary renderer/font identity")
    rows = [{"id": c["id"], "sameSourceBytes": c["sameSourceBytes"],
             "sameNativeBinaryBytes": c["sameNativeBinaryBytes"], "initialDelta": c["initialDelta"],
             "changedRenderFingerprints": [k for k, v in c["renderFingerprintEquality"].items() if not v],
             "cycleDeltas": c["cycleDeltas"]} for c in derived["cases"]]
    require(summary["casesSummary"] == rows, "Summary per-case comparison binding")
    pixel_pairs, pixel_rejected = check_word14(root, args.self_test)
    source_packages, source_rejected = check_word14_source(root, args.self_test)
    print(json.dumps({"verified": True, "parserCommit": COMMIT, "parserTree": TREE,
          "retainedSources": len(sources), "recomputedRenderComparisons": count,
          "nativeCases": 24, "roundtripCycles": 72, "artifactCheck": artifact_check,
          "comparisonReproduced": True, "semanticCorruptionsRejected": rejected + pixel_rejected + source_rejected,
          "word14PixelComparisonsRecomputed": pixel_pairs, "word14SourcePackagesBound": source_packages,
          "hostedCi": hosted_result}, sort_keys=True))


if __name__ == "__main__":
    main()
