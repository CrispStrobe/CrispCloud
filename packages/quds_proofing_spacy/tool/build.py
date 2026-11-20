#!/usr/bin/env python3
"""Build the CrispEmbed spaCy runtime library for a host app bundle.

Fetches CrispEmbed at one immutable commit (the source of the published
v2 runtime capsules, which also opens the English and French bundles) with
its pinned ggml submodule, and PCRE2 at one immutable commit; checks each
checkout against its pin; builds PCRE2 statically and the standalone
`tools/spacy` target as a shared library exactly as CrispEmbed's platform
packaging does (Release, CPU only, static PCRE2, @rpath install name, macOS
13 deployment target); and writes a receipt naming and hashing the library.

Only the native library is built. The model bundles (GGUF data) stay
separate downloads that the app verifies against compiled-in digests.

    python3 tool/build.py --native
    python3 tool/build.py --native --install-native <App>.app/Contents/Frameworks \\
        --install-licenses <App>.app/Contents/Resources/spacy-licenses
    python3 tool/build.py --license-bundle   # refresh licenses/ from the pinned source

`--crispembed-repo` may name a local clone or mirror; the checked-out
commit must still equal the pin.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys

PACKAGE = Path(__file__).resolve().parents[1]
LICENSES = PACKAGE / "licenses"
CRISPEMBED = {
    "repository": "https://github.com/CrispStrobe/CrispEmbed",
    # Merge of CrispEmbed PR #244: the source of the published v2 runtime
    # capsules (see lib/src/distribution.dart, `_v2Source`).
    "commit": "45b057700880e125d701d941a9e3123679960d35",
    "ggml": "3a27b6c665b191cb230be367db5c52d81dd3e2ac",
}
PCRE2 = {
    "repository": "https://github.com/PCRE2Project/pcre2.git",
    # The PCRE2 commit CrispEmbed's platform packaging links statically.
    "commit": "b2bd4254b379b9d7dc9a3dda060a7e27009ccdff",
}
LIBRARY = "libcrispembed-spacy.dylib"
DEPLOYMENT_TARGET = "13.0"
# Recorded in the receipt; a receipt without it predates reproducible builds
# and is rebuilt rather than reused.
BUILD_PATH_PREFIX = "/quds-spacy-build"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(args, cwd=None, capture=False):
    print(" ".join(str(a) for a in args), file=sys.stderr, flush=True)
    result = subprocess.run([str(a) for a in args], cwd=cwd, check=True,
                            stdout=subprocess.PIPE if capture else sys.stderr, text=True)
    return result.stdout.strip() if capture else ""


def checkout(repository: str, commit: str, target: Path) -> None:
    """Shallow-fetch exactly [commit] into [target] and verify it."""
    if (target / ".git").exists():
        try:
            if run(["git", "rev-parse", "HEAD"], cwd=target, capture=True) == commit:
                return
        except subprocess.CalledProcessError:
            pass
        shutil.rmtree(target)
    target.mkdir(parents=True, exist_ok=True)
    run(["git", "init", "-q"], cwd=target)
    run(["git", "fetch", "-q", "--depth", "1", repository, commit], cwd=target)
    run(["git", "checkout", "-q", "--detach", "FETCH_HEAD"], cwd=target)
    head = run(["git", "rev-parse", "HEAD"], cwd=target, capture=True)
    if head != commit:
        raise SystemExit(f"{repository} checked out {head}, expected {commit}")


def fetch_source(work: Path, repository: str) -> tuple[Path, Path]:
    crispembed = work / f"crispembed-{CRISPEMBED['commit'][:12]}"
    checkout(repository, CRISPEMBED["commit"], crispembed)
    recorded = run(["git", "ls-tree", "HEAD", "ggml"], cwd=crispembed, capture=True).split()
    if len(recorded) < 3 or recorded[2] != CRISPEMBED["ggml"]:
        raise SystemExit(f"CrispEmbed records another ggml commit: {recorded}")
    ggml = crispembed / "ggml"
    if not (ggml / "CMakeLists.txt").exists() or \
            run(["git", "rev-parse", "HEAD"], cwd=ggml, capture=True) != CRISPEMBED["ggml"]:
        run(["git", "submodule", "update", "--init", "--depth", "1", "ggml"], cwd=crispembed)
    if run(["git", "rev-parse", "HEAD"], cwd=ggml, capture=True) != CRISPEMBED["ggml"]:
        raise SystemExit("ggml submodule differs from its pin")
    status = run(["git", "status", "--porcelain", "--ignore-submodules=none"], cwd=crispembed, capture=True)
    if status:
        raise SystemExit(f"CrispEmbed checkout is not clean:\n{status}")
    pcre2 = work / f"pcre2-{PCRE2['commit'][:12]}"
    checkout(PCRE2["repository"], PCRE2["commit"], pcre2)
    return crispembed, pcre2


def build(crispembed: Path, pcre2: Path, output: Path, jobs: int) -> Path:
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("This build is defined for macOS arm64 app bundles")
    # Reproducible bytes: compiled-in source paths (__FILE__ in ggml/PCRE2
    # assertions) would otherwise embed the checkout location, so every clone
    # produced a different library and digest-bound qualification could not
    # survive a rebuild. The linker's LC_UUID is a content hash and the
    # linker/ad hoc signatures are deterministic, so with this map the same
    # source and toolchain give the same bytes in any directory.
    prefix_map = f"-ffile-prefix-map={output}={BUILD_PATH_PREFIX}"
    apple = ["-DCMAKE_OSX_ARCHITECTURES=arm64", f"-DCMAKE_OSX_DEPLOYMENT_TARGET={DEPLOYMENT_TARGET}",
             f"-DCMAKE_C_FLAGS={prefix_map}", f"-DCMAKE_CXX_FLAGS={prefix_map}"]
    pcre_build, prefix = output / "cmake-pcre2", output / "pcre2-install"
    run(["cmake", "-S", pcre2, "-B", pcre_build, "-DCMAKE_BUILD_TYPE=Release", *apple,
         "-DBUILD_SHARED_LIBS=OFF", "-DPCRE2_STATIC_PIC=ON", "-DPCRE2_BUILD_PCRE2_8=ON",
         "-DPCRE2_BUILD_PCRE2_16=OFF", "-DPCRE2_BUILD_PCRE2_32=OFF", "-DPCRE2_BUILD_PCRE2GREP=OFF",
         "-DPCRE2_BUILD_TESTS=OFF", f"-DCMAKE_INSTALL_PREFIX={prefix}"])
    run(["cmake", "--build", pcre_build, "--parallel", str(jobs)])
    run(["cmake", "--install", pcre_build])
    native_build, install = output / "cmake-native", output / "native-install"
    run(["cmake", "-S", crispembed / "tools/spacy", "-B", native_build, "-DCMAKE_BUILD_TYPE=Release", *apple,
         f"-DSPACY_PCRE2_INCLUDE_DIR={prefix / 'include'}",
         f"-DSPACY_PCRE2_LIBRARY={prefix / 'lib/libpcre2-8.a'}",
         "-DCMAKE_INSTALL_NAME_DIR=@rpath", "-DCMAKE_INSTALL_RPATH=@loader_path",
         "-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON"])
    run(["cmake", "--build", native_build, "--parallel", str(jobs), "--target", "crispembed-spacy"])
    if install.exists():
        shutil.rmtree(install)
    run(["cmake", "--install", native_build, "--prefix", install])
    library = install / "lib" / LIBRARY
    links = run(["otool", "-L", library], capture=True).splitlines()[1:]
    foreign = [line.split()[0] for line in links
               if not line.split()[0].startswith(("/usr/lib/", "/System/", "@rpath/" + LIBRARY))]
    if foreign:
        raise SystemExit(f"{LIBRARY} links outside the system: {foreign}")
    (output / "native").mkdir(parents=True, exist_ok=True)
    target = output / "native" / LIBRARY
    shutil.copyfile(library, target)
    notices = output / "native-licenses"
    if notices.exists():
        shutil.rmtree(notices)
    shutil.copytree(install / "share/licenses/crispembed-spacy", notices)
    return target


def license_bundle(crispembed: Path) -> None:
    """Copy the runtime notices from the pinned source into licenses/."""
    if LICENSES.exists():
        shutil.rmtree(LICENSES)
    LICENSES.mkdir()
    files = {
        "CrispEmbed-LICENSE": crispembed / "LICENSE",
        "ggml-LICENSE": crispembed / "ggml/LICENSE",
        "THIRD_PARTY_NOTICES": crispembed / "tools/spacy/THIRD_PARTY_NOTICES",
    }
    for path in sorted((crispembed / "tools/spacy/notices").iterdir()):
        if path.is_file():
            files[f"notices/{path.name}"] = path
    manifest = {"schema_version": 1, "crispembed": CRISPEMBED, "pcre2": PCRE2, "notices": {}}
    for name, source in files.items():
        target = LICENSES / name
        target.parent.mkdir(parents=True, exist_ok=True)
        data = source.read_bytes()
        target.write_bytes(data)
        manifest["notices"][name] = sha(data)
    (LICENSES / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                                            encoding="utf-8", newline="\n")


def verify_licenses() -> dict:
    manifest = json.loads((LICENSES / "manifest.json").read_text(encoding="utf-8"))
    if manifest["crispembed"] != CRISPEMBED or manifest["pcre2"] != PCRE2:
        raise SystemExit("licenses/manifest.json names other sources; run --license-bundle")
    for name, digest in manifest["notices"].items():
        if sha((LICENSES / name).read_bytes()) != digest:
            raise SystemExit(f"notice differs from the licence manifest: {name}")
    return manifest


def install_native(output: Path, destination: Path) -> dict:
    receipt = json.loads((output / "build-receipt.json").read_text(encoding="utf-8"))
    name = f"native/{LIBRARY}"
    if sha((output / name).read_bytes()) != receipt["files"][name]:
        raise SystemExit(f"changed build artifact: {name}")
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(output / name, destination / LIBRARY)
    return {"destination": str(destination), "files": [name]}


def install_licenses(output: Path, destination: Path) -> None:
    manifest = verify_licenses()
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    for name in manifest["notices"]:
        (destination / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(LICENSES / name, destination / name)
    shutil.copyfile(LICENSES / "manifest.json", destination / "manifest.json")
    shutil.copyfile(PACKAGE / "LICENSE", destination / "LICENSE.adapter")
    receipt = output / "build-receipt.json"
    if receipt.exists():
        shutil.copyfile(receipt, destination / "build-receipt.json")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--native", action="store_true", help="Build the macOS arm64 library")
    parser.add_argument("--license-bundle", action="store_true")
    parser.add_argument("--output", type=Path, default=PACKAGE / "build")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--crispembed-repo", default=CRISPEMBED["repository"],
                        help="Git URL or local clone to fetch the pinned CrispEmbed commit from")
    parser.add_argument("--install-native", type=Path,
                        help="Copy the built library into this host directory (e.g. <App>.app/Contents/Frameworks)")
    parser.add_argument("--install-licenses", type=Path,
                        help="Copy the runtime notices and licence manifest into this directory")
    parser.add_argument("--keep-source", action="store_true",
                        help="Keep the source checkouts and CMake trees (removed by default: they are "
                             "large and the CrispEmbed checkout contains unrelated Dart files)")
    args = parser.parse_args()
    if args.install_native and not args.native:
        parser.error("--install-native requires --native")
    output = args.output.resolve()
    try:
        build_outputs(args, output)
    finally:
        if not args.keep_source:
            for name in ("source", "cmake-pcre2", "cmake-native", "pcre2-install", "native-install"):
                shutil.rmtree(output / name, ignore_errors=True)
    if args.install_native:
        print(json.dumps(install_native(output, args.install_native.resolve())))
    if args.install_licenses:
        install_licenses(output, args.install_licenses.resolve())
        print(json.dumps({"licenses": str(args.install_licenses.resolve())}))
    return 0


def build_outputs(args, output: Path) -> None:
    sources = None
    if args.license_bundle:
        sources = fetch_source(output / "source", args.crispembed_repo)
        license_bundle(sources[0])
    if args.native:
        verify_licenses()
        receipt_path = output / "build-receipt.json"
        library = output / "native" / LIBRARY
        current = None
        if receipt_path.exists() and library.exists():
            current = json.loads(receipt_path.read_text(encoding="utf-8"))
            if current.get("crispembed") != CRISPEMBED or current.get("pcre2") != PCRE2 or \
                    current.get("file_prefix_map") != BUILD_PATH_PREFIX or \
                    current.get("files", {}).get(f"native/{LIBRARY}") != sha(library.read_bytes()):
                current = None
        if current is None:
            sources = sources or fetch_source(output / "source", args.crispembed_repo)
            build(*sources, output, args.jobs)
            receipt = {"crispembed": CRISPEMBED, "pcre2": PCRE2, "platform": platform.platform(),
                       "deployment_target": DEPLOYMENT_TARGET, "file_prefix_map": BUILD_PATH_PREFIX,
                       "license_manifest_sha256": sha((LICENSES / "manifest.json").read_bytes()),
                       "files": {f"native/{LIBRARY}": sha(library.read_bytes())}}
            receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                    encoding="utf-8", newline="\n")
        print(json.dumps({f"native/{LIBRARY}": (sha(library.read_bytes()), library.stat().st_size)}))


if __name__ == "__main__":
    sys.exit(main())
