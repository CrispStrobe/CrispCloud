"""Prepare an isolated real-platform ebook reader/editor integration app.

Create it with `flutter create --project-name crisp_native_ebook_smoke
--platforms=<platform> <output>` first. It links the production reader, EPUB
editor and native Kindle code asset, without unrelated CrispCloud providers.
"""
from pathlib import Path
import argparse
import json
import plistlib
import re
import shutil
import xml.etree.ElementTree as ET


def prepare(output: Path, platform: str) -> None:
    package = Path(__file__).resolve().parents[1]
    repository = package.parents[1]
    output = output.resolve()
    manifest = output / "pubspec.yaml"
    if (not manifest.is_file() or
            "name: crisp_native_ebook_smoke" not in manifest.read_text(encoding="utf-8") or
            not (output / platform).is_dir()):
        raise ValueError("Create the named Flutter project and requested platform first.")

    manifest.write_text(f"""name: crisp_native_ebook_smoke
publish_to: none
environment:
  sdk: '>=3.8.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  archive: ^4.6.0
  crisp_ebook:
    path: {json.dumps(str(package.parent / 'crisp_ebook'))}
  crisp_ebook_conversion:
    path: {json.dumps(str(package.parent / 'crisp_ebook_conversion'))}
  crisp_ebook_reader:
    path: {json.dumps(str(package))}
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  flutter_lints: ^5.0.0
flutter:
  uses-material-design: true
""", encoding="utf-8")
    tests = output / "integration_test"
    tests.mkdir(exist_ok=True)
    shutil.copyfile(package / "test/native/reader_platform_integration.dart",
                    tests / "reader_platform_test.dart")

    if platform == "android":
        namespace = "http://schemas.android.com/apk/res/android"
        ET.register_namespace("android", namespace)
        android_manifest = output / "android/app/src/main/AndroidManifest.xml"
        tree = ET.parse(android_manifest)
        root = tree.getroot()
        permission = "android.permission.INTERNET"
        if not any(element.get(f"{{{namespace}}}name") == permission
                   for element in root.findall("uses-permission")):
            ET.SubElement(root, "uses-permission", {f"{{{namespace}}}name": permission})
        application = root.find("application")
        if application is None:
            raise ValueError("The Flutter Android manifest has no application.")
        application.set(f"{{{namespace}}}networkSecurityConfig",
                        "@xml/ebook_network_security_config")
        application.attrib.pop(f"{{{namespace}}}usesCleartextTraffic", None)
        tree.write(android_manifest, encoding="utf-8", xml_declaration=True)
        resources = output / "android/app/src/main/res/xml"
        resources.mkdir(exist_ok=True)
        # Exercise the application's exact loopback-only exception, not a
        # permissive testing policy that could hide a release configuration bug.
        shutil.copyfile(repository / "android/app/src/main/res/xml/ebook_network_security_config.xml",
                        resources / "ebook_network_security_config.xml")
        gradle = output / "android/app/build.gradle.kts"
        text = gradle.read_text(encoding="utf-8")
        text, count = re.subn(r"ndkVersion\s*=\s*[^\n]+",
                              'ndkVersion = "28.2.13676358"', text)
        if count != 1:
            raise ValueError("Cannot identify the generated Android NDK setting.")
        text = re.sub(r"minSdk\s*=\s*flutter.minSdkVersion",
                      "minSdk = maxOf(flutter.minSdkVersion, 24)", text)
        gradle.write_text(text, encoding="utf-8")

    if platform in {"ios", "macos"}:
        target = output / platform / "Runner/Info.plist"
        with target.open("rb") as file:
            info = plistlib.load(file)
        with (repository / platform / "Runner/Info.plist").open("rb") as file:
            production = plistlib.load(file)
        info["NSAppTransportSecurity"] = production["NSAppTransportSecurity"]
        with target.open("wb") as file:
            plistlib.dump(info, file, sort_keys=False)
        minimum = "15.0" if platform == "ios" else "12.0"
        setting = "IPHONEOS_DEPLOYMENT_TARGET" if platform == "ios" else "MACOSX_DEPLOYMENT_TARGET"
        project = output / platform / "Runner.xcodeproj/project.pbxproj"
        source = project.read_text(encoding="utf-8")
        source = re.sub(rf"{setting}\s*=\s*[0-9.]+;", f"{setting} = {minimum};", source)
        project.write_text(source, encoding="utf-8")
        podfile = output / platform / "Podfile"
        if podfile.exists():
            source = podfile.read_text(encoding="utf-8")
            platform_name = "ios" if platform == "ios" else "osx"
            source, count = re.subn(r"(?m)^\s*#?\s*platform\s*:\w+,\s*'[^']+'",
                                    f"platform :{platform_name}, '{minimum}'", source)
            if count != 1:
                raise ValueError("Cannot identify the generated CocoaPods platform.")
            podfile.write_text(source, encoding="utf-8")
        if platform == "macos":
            for name in ["DebugProfile.entitlements", "Release.entitlements"]:
                entitlement = output / "macos/Runner" / name
                with entitlement.open("rb") as file:
                    entries = plistlib.load(file)
                entries["com.apple.security.network.client"] = True
                entries["com.apple.security.network.server"] = True
                with entitlement.open("wb") as file:
                    plistlib.dump(entries, file, sort_keys=False)

    print(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--platform", choices=["android", "ios", "macos", "windows", "linux"], required=True)
    arguments = parser.parse_args()
    prepare(arguments.output, arguments.platform)
