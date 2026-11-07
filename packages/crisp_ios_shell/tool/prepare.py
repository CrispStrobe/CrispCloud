#!/usr/bin/env python3
"""Build a checksum-verified, curated ios_system + Dash distribution.

No prebuilt executable is run. Source archives are immutable commit URLs;
local patches and this script are part of the corresponding source. macOS/Xcode
is required for binaries; --verify-only validates sources/patches on any host.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

PACKAGE = Path(__file__).resolve().parents[1]
BUILD = PACKAGE / ".build"
MANIFEST = PACKAGE / "tool/sources.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(source: dict, destination: Path) -> None:
    """Cache only bytes matching the reviewed digest; never trust cache existence."""
    if destination.exists() and sha256(destination) == source["sha256"]:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".download")
    try:
        request = urllib.request.Request(source["url"], headers={"User-Agent": "CrispCloud-source-builder/1"})
        with urllib.request.urlopen(request, timeout=90) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        actual = sha256(temporary)
        if actual != source["sha256"]:
            raise RuntimeError(f"Source digest mismatch for {destination.name}: {actual}")
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def extract_source(archive: Path, destination: Path, *, omit: set[str] | None = None) -> None:
    """Reject escaping archive members, devices and links before extracting."""
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    with tarfile.open(archive, "r:gz") as source:
        members = [member for member in source.getmembers()
                   if "/".join(Path(member.name).parts[1:]) not in (omit or set())]
        roots = {Path(member.name).parts[0] for member in members if member.name}
        if len(roots) != 1:
            raise RuntimeError("Source archive must contain one root directory")
        root = next(iter(roots))
        for member in members:
            path = Path(member.name)
            if path.is_absolute() or ".." in path.parts:
                raise RuntimeError(f"Unsafe source path: {member.name}")
            if member.isdev() or member.isfifo():
                raise RuntimeError(f"Unexpected source member: {member.name}")
            if member.issym() or member.islnk():
                target = Path(member.linkname)
                if target.is_absolute():
                    raise RuntimeError(f"Absolute source link: {member.name}")
                # Resolve lexical links without following any existing filesystem links.
                parts = list(path.parent.parts if member.issym() else ())
                for part in target.parts:
                    if part == "..":
                        if not parts:
                            raise RuntimeError(f"Escaping source link: {member.name}")
                        parts.pop()
                    elif part != ".":
                        parts.append(part)
                if not parts or parts[0] != root:
                    raise RuntimeError(f"Escaping source link: {member.name}")
        # Python 3.12+ supports the stricter data filter. The checks above also
        # protect the macOS system Python versions used by older Xcode runners.
        try:
            source.extractall(destination, members=members, filter="data")
        except TypeError:
            source.extractall(destination, members=members)
    extracted = destination / root
    for item in list(extracted.iterdir()):
        item.rename(destination / item.name)
    extracted.rmdir()


def run(arguments: list[str | Path], *, cwd: Path | None = None, env: dict | None = None) -> None:
    command = [str(value) for value in arguments]
    print("+", shlex.join(command), flush=True)
    subprocess.run(command, cwd=cwd, env=env, check=True)


def prepare_sources(manifest: dict) -> dict[str, Path]:
    result = {}
    for name, source in manifest["sources"].items():
        archive = BUILD / "downloads" / f"{name}-{source['commit']}.tar.gz"
        download(source, archive)
        destination = BUILD / "sources" / name
        extract_source(archive, destination, omit={"missing"} if name == "dash" else None)
        patch = PACKAGE / "patches" / f"{name}.patch"
        run(["patch", "--batch", "--forward", "-p1", "-i", patch], cwd=destination)
        result[name] = destination
    # The pinned Dash archive has one absolute symlink to its author's automake.
    # Omit that specific build-only link and substitute the reviewed exact file.
    # The archive also omits compile/install-sh/depcomp required by its generated
    # configure/Makefile.in files. Vendor the matching immutable automake version.
    for filename, record in manifest["build_helpers"].items():
        helper = PACKAGE / "tool" / filename
        if sha256(helper) != record["sha256"]:
            raise RuntimeError(f"Vendored automake support script digest mismatch: {filename}")
        destination = result["dash"] / filename.removeprefix("automake-")
        shutil.copy2(helper, destination)
        destination.chmod(0o755)
    # Dash and the runtime must use exactly the same stream/getopt/exec API.
    shutil.copy2(result["ios_system"] / "ios_error.h", result["dash"] / "ios_error.h")
    return result


def source_notices(sources: dict[str, Path]) -> str:
    """Retain upstream license texts and copyright/license comment blocks.

    Include the relevant command source directories, including their helpers.
    Extra notices are harmless; dropping source-header conditions is not.
    """
    sections = []
    groups: dict[str, list[str]] = {}
    roots = {
        "ios_system": ["file_cmds", "shell_cmds", "text_cmds", "libarchive", "libutil", "less-34", "awk-awk-35", "ios_system", "text"],
        "dash": ["src"],
    }
    for name, source in sources.items():
        candidates = list(source.glob("*.c")) + list(source.glob("*.m")) + list(source.glob("*.h"))
        candidates += [source / entry for entry in ("LICENSE", "COPYING") if (source / entry).exists()]
        for folder in roots[name]:
            if (source / folder).is_dir():
                candidates += list((source / folder).rglob("*"))
        for path in sorted(set(candidates)):
            if not path.is_file() or path.is_symlink():
                continue
            relative = f"{name}/{path.relative_to(source)}"
            if re.search(r"^(COPYING|LICENSE|LICENCE)([._-].*)?$", path.name, re.I):
                value = path.read_text(errors="replace").strip()
                if value:
                    groups.setdefault(value, []).append(relative)
            elif path.suffix in {".c", ".h", ".m", ".cc", ".cpp"}:
                content = path.read_text(errors="replace")[:20000]
                for comment in re.findall(r"/\*.*?\*/", content, re.S):
                    if re.search(r"copyright|redistribution|general public license|permission is hereby", comment, re.I):
                        groups.setdefault(comment.strip(), []).append(relative)
    # These pinned build-only shell helpers carry licenses/exceptions in '#'
    # headers rather than C comments. Retain those conditions in the aggregate
    # notices as well as in each redistributed source file.
    helpers = json.loads(MANIFEST.read_text())["build_helpers"]
    for filename in sorted(helpers):
        header = []
        for line in (PACKAGE / "tool" / filename).read_text().splitlines():
            if line.startswith("#!") or line.startswith("scriptversion="):
                continue
            if line.startswith("#"):
                header.append(line[1:].removeprefix(" "))
            elif not line.strip():
                header.append("")
            else:
                break
        notice = "\n".join(header).strip()
        if not notice or "Copyright" not in notice:
            raise RuntimeError(f"Missing vendored build-helper notice: {filename}")
        groups.setdefault(notice, []).append(f"tool/{filename}")
    for notice, origins in sorted(groups.items(), key=lambda pair: pair[1][0]):
        sections.append("Sources: " + ", ".join(sorted(set(origins))) + "\n\n" + notice)
    own = (PACKAGE / "licenses/CrispCloud-AGPL-3.0.txt").read_text()
    gpl = (PACKAGE / "licenses/GPL-2.0.txt").read_text()
    introduction = (
        "CrispCloud embedded iOS shell\n\n"
        "CrispCloud integration code is licensed under AGPL-3.0. Third-party components retain\n"
        "their own terms below. Dash COPYING explicitly identifies GPL-2.0-or-later material\n"
        "in the output of mksignames.c; do not describe the entire binary as BSD-only.\n"
        "Pinned Automake build helpers retain their GPL-2.0-or-later distribution exception\n"
        "and X Consortium notices below; these scripts are corresponding build source.\n"
        "Exact corresponding source, patches and reproducible build instructions: tool/sources.json,\n"
        "patches/, tool/prepare.py and UPSTREAM.md in packages/crisp_ios_shell at\n"
        "https://github.com/CrispStrobe/CrispCloud\n\n"
    )
    return introduction + own + "\n\n" + "\n\n".join(sections) + "\n\nGNU GPL version 2\n\n" + gpl


def fingerprint(manifest: dict) -> dict:
    return {
        "manifest": manifest,
        "preparation_sha256": sha256(Path(__file__)),
        "patches": {path.name: sha256(path) for path in sorted((PACKAGE / "patches").glob("*.patch"))},
        "commands_sha256": sha256(PACKAGE / "ios/Resources/commands.plist"),
    }


def output_is_current(stamp: dict, expected: dict, frameworks: Path) -> bool:
    if stamp.get("inputs") != expected or not stamp.get("outputs"):
        return False
    for relative, checksum in stamp["outputs"].items():
        path = frameworks / relative
        if not path.is_file() or sha256(path) != checksum:
            return False
    return True


def sdk_path(sdk: str) -> str:
    return subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()


def build_runtime(source: Path, manifest: dict) -> dict[str, Path]:
    products = BUILD / "runtime-products"
    if products.exists():
        shutil.rmtree(products)
    result = {}
    for sdk, arch in (("iphoneos", "arm64"), ("iphonesimulator", "arm64 x86_64")):
        # The upstream utility targets have no explicit dependency edge to core,
        # so build ios_system first and then each selected framework in order.
        for target in manifest["targets"]:
            run([
                "xcodebuild", "-quiet", "-project", source / "ios_system.xcodeproj",
                "-target", target, "-configuration", "Release", "-sdk", sdk,
                f"ARCHS={arch}", "ONLY_ACTIVE_ARCH=NO", "EXCLUDED_ARCHS=",
                f"IPHONEOS_DEPLOYMENT_TARGET={manifest['ios_deployment_target']}",
                "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "ENABLE_BITCODE=NO",
                "SKIP_INSTALL=NO", "BUILD_LIBRARY_FOR_DISTRIBUTION=YES",
                "SUPPORTED_PLATFORMS=iphoneos iphonesimulator", "TARGETED_DEVICE_FAMILY=1,2",
                "OTHER_CFLAGS=$(inherited) -Wno-int-conversion",
                f"SYMROOT={products}", f"OBJROOT={BUILD / 'runtime-objects' / sdk}", "build",
            ], cwd=source)
        result[sdk] = products / f"Release-{sdk}"
    return result


def build_dash(source: Path, products: dict[str, Path], manifest: dict) -> None:
    mac_sdk = sdk_path("macosx")
    compiler = subprocess.check_output(["xcrun", "--find", "clang"], text=True).strip()
    host_arch = platform.machine()
    binaries = {}
    deployment = manifest["ios_deployment_target"]
    for sdk, arch in (("iphoneos", "arm64"), ("iphonesimulator", "arm64"), ("iphonesimulator", "x86_64")):
        build = BUILD / "dash-build" / f"{sdk}-{arch}"
        if build.exists():
            shutil.rmtree(build)
        shutil.copytree(source, build, symlinks=True)
        target = f"{arch}-apple-ios{deployment}" + ("-simulator" if sdk == "iphonesimulator" else "")
        sdkroot = sdk_path(sdk)
        common = ["-target", target, "-isysroot", sdkroot, "-DJOBS=0", "-Dstat64=stat", "-Dlstat64=lstat",
                  "-Dfstat64=fstat", "-DUSE_GLIBC_STDIO=1", "-DFLUSHERR=1", "-I", str(build)]
        env = os.environ.copy()
        env.update({
            "CC": compiler, "CXX": compiler,
            "CC_FOR_BUILD": shlex.join([compiler, "-isysroot", mac_sdk, "-DJOBS=0"]),
            "CFLAGS": shlex.join(["-std=gnu17", "-fPIC", *common]),
            "CPPFLAGS": shlex.join(common), "CXXFLAGS": shlex.join(common),
            "LDFLAGS": shlex.join([*common, "-dynamiclib", "-Wl,-headerpad_max_install_names", "-F", str(products[sdk]), "-framework", "ios_system"]),
        })
        host = "armv8" if arch == "arm64" else "x86_64"
        run(["./configure", f"--build={host_arch}-apple-darwin", f"--host={host}-apple-darwin", "cross_compiling=yes", "--without-libedit"], cwd=build, env=env)
        run(["make", f"-j{min(os.cpu_count() or 2, 8)}"], cwd=build, env=env)
        binaries[(sdk, arch)] = build / "src/dash"
    simulator = BUILD / "dash-simulator"
    run(["xcrun", "lipo", "-create", binaries[("iphonesimulator", "arm64")], binaries[("iphonesimulator", "x86_64")], "-output", simulator])
    for sdk, executable in (("iphoneos", binaries[("iphoneos", "arm64")]), ("iphonesimulator", simulator)):
        for name in manifest["dash_variants"]:
            framework = products[sdk] / f"{name}.framework"
            framework.mkdir(exist_ok=True)
            shutil.copy2(executable, framework / name)
            run(["xcrun", "install_name_tool", "-id", f"@rpath/{name}.framework/{name}", framework / name])
            info = {
                "CFBundleDevelopmentRegion": "en", "CFBundleExecutable": name,
                "CFBundleIdentifier": f"org.crispcloud.shell.{name}", "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": name, "CFBundlePackageType": "FMWK", "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1", "MinimumOSVersion": deployment,
                "CFBundleSupportedPlatforms": ["iPhoneOS" if sdk == "iphoneos" else "iPhoneSimulator"],
            }
            (framework / "Info.plist").write_bytes(plistlib.dumps(info))
            (framework / "Headers").mkdir(exist_ok=True)
            (framework / "Headers" / f"{name}.h").write_text("#pragma once\nint dash_main(int argc, char **argv);\n")
            (framework / "Modules").mkdir(exist_ok=True)
            (framework / "Modules/module.modulemap").write_text(f'framework module {name} {{\n  umbrella header "{name}.h"\n  export *\n}}\n')


def validate_command_symbols(products: dict[str, Path], manifest: dict) -> None:
    """Fail before packaging if a command's actual image cannot export its entry point."""
    commands = plistlib.loads((PACKAGE / "ios/Resources/commands.plist").read_bytes())
    expected: dict[str, set[str]] = {name: {"dash_main"} for name in manifest["dash_variants"]}
    for library, symbol, _, _ in commands.values():
        name = "ios_system" if library == "SELF" else Path(library).name
        expected.setdefault(name, set()).add(symbol)
    for sdk, folder in products.items():
        architectures = ("arm64", "x86_64") if sdk == "iphonesimulator" else ("arm64",)
        for name, symbols in sorted(expected.items()):
            binary = folder / f"{name}.framework" / name
            for architecture in architectures:
                listing = subprocess.check_output(
                    ["xcrun", "nm", "-arch", architecture, "-gU", str(binary)], text=True)
                exported = {line.split()[-1] for line in listing.splitlines() if line.split()}
                missing = {symbol for symbol in symbols if f"_{symbol}" not in exported}
                if missing:
                    raise RuntimeError(f"{sdk}/{architecture}/{name} is missing command exports: {', '.join(sorted(missing))}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true", help="verify/extract/patch sources and refresh notices without Xcode")
    parser.add_argument("--force", action="store_true", help="ignore an otherwise current binary cache")
    arguments = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    inputs = fingerprint(manifest)
    output = PACKAGE / "ios/Frameworks"
    stamp_file = PACKAGE / "ios/Resources/BuildProvenance.json"
    if not arguments.verify_only:
        if platform.system() != "Darwin":
            parser.error("Native preparation needs macOS and Xcode; use --verify-only on this host")
        inputs["xcode"] = subprocess.check_output(["xcodebuild", "-version"], text=True).strip()
        if stamp_file.exists() and not arguments.force:
            try:
                if output_is_current(json.loads(stamp_file.read_text()), inputs, output):
                    print("Verified cached iOS shell frameworks.")
                    return
            except (OSError, ValueError):
                pass
    BUILD.mkdir(parents=True, exist_ok=True)
    sources = prepare_sources(manifest)
    notices = source_notices(sources)
    (PACKAGE / "LICENSE").write_text(notices)
    (PACKAGE / "ios/Resources/NativeNotices.txt").write_text(notices)
    if arguments.verify_only:
        print("Verified immutable source archives and applied all patches; refreshed complete notices.")
        return
    products = build_runtime(sources["ios_system"], manifest)
    build_dash(sources["dash"], products, manifest)
    validate_command_symbols(products, manifest)
    with tempfile.TemporaryDirectory(prefix="frameworks-", dir=BUILD) as staging_name:
        staging = Path(staging_name)
        for name in manifest["targets"] + manifest["dash_variants"]:
            run(["xcodebuild", "-create-xcframework", "-framework", products["iphoneos"] / f"{name}.framework",
                 "-framework", products["iphonesimulator"] / f"{name}.framework", "-output", staging / f"{name}.xcframework"])
        outputs = {str(path.relative_to(staging)): sha256(path) for path in sorted(staging.rglob("*")) if path.is_file()}
        if output.exists():
            shutil.rmtree(output)
        shutil.copytree(staging, output, symlinks=True)
    stamp_file.write_text(json.dumps({"inputs": inputs, "outputs": outputs}, indent=2, sort_keys=True) + "\n")
    print(f"Prepared {len(manifest['targets']) + len(manifest['dash_variants'])} XCFrameworks for device arm64 and simulator arm64/x86_64.")


if __name__ == "__main__":
    main()
