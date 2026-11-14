#!/usr/bin/env python3
"""Compile and run the real Office copy adapter in an installed Chromium.

Requires resolved Dart packages and already-installed Playwright/Chromium. This
does not install packages, build Flutter, or open an authenticated site. The
download is captured through the browser's real download event; instrumentation
observes native URL and anchor calls while preserving their original behavior.
The default uses the application's resolved dependencies. An explicit --packages
configuration supports a smaller SDK-only probe, identified separately in both
receipts; it does not claim resolution of the full application's dependency graph.
"""

import argparse
from functools import partial
from hashlib import sha256
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "test/support/office_device_export_web_acceptance.dart"
EXPECTED_NAME = "Recovery_ budget_.xlsx"
EXPECTED_BYTES = bytes(range(256))

OBSERVE = """
(() => {
  const trace = window.officeCopyTrace = {created: [], clicked: [], revoked: []};
  const create = URL.createObjectURL;
  URL.createObjectURL = function (blob) {
    const url = create.call(this, blob);
    trace.created.push({url, size: blob.size, type: blob.type, time: performance.now()});
    return url;
  };
  const click = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    trace.clicked.push({url: this.href, name: this.download,
      connected: this.isConnected, display: this.style.display,
      time: performance.now()});
    return click.call(this);
  };
  const revoke = URL.revokeObjectURL;
  URL.revokeObjectURL = function (url) {
    trace.revoked.push({url, time: performance.now()});
    return revoke.call(this, url);
  };
})();
"""


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, format, *arguments):
        pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def digest(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", default=shutil.which("dart"))
    parser.add_argument("--chromium", default=shutil.which("chromium"))
    parser.add_argument("--compile-only", action="store_true",
                        help="Compile the real wrapper/adapter without claiming browser execution")
    parser.add_argument("--packages", type=Path,
                        default=ROOT / ".dart_tool/package_config.json",
                        help="Explicit package configuration for a scoped dependency probe; "
                             "defaults to the application's resolved package configuration")
    parser.add_argument("--output", type=Path, default=ROOT / "build/office-web-copy")
    args = parser.parse_args()
    if not args.dart or (not args.compile_only and not args.chromium):
        parser.error("Provide already-installed Dart and Chromium executables")
    packages = args.packages.resolve()
    if not packages.is_file():
        parser.error("The selected package_config.json must already exist")
    application_packages = (ROOT / ".dart_tool/package_config.json").resolve()
    dependency_resolution = {
        "scope": "application" if packages == application_packages else "explicit_package_config",
        "package_config": str(packages.relative_to(ROOT))
                          if packages.is_relative_to(ROOT) else str(packages),
        "package_config_sha256": digest(packages),
        "application_lock_sha256": digest(ROOT / "pubspec.lock"),
    }
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    compiled = output / "acceptance.js"
    environment = dict(os.environ, CI="true", BOT="true",
                       FLUTTER_SUPPRESS_ANALYTICS="true", DART_SUPPRESS_ANALYTICS="true")
    result = subprocess.run(
        [args.dart, "compile", "js", "--packages=" + str(packages), "-O1",
         "-o", str(compiled), str(SOURCE)],
        cwd=ROOT, env=environment, text=True, capture_output=True, timeout=180,
    )
    (output / "compile.log").write_text(result.stdout + result.stderr)
    require(result.returncode == 0, "Dart-to-JavaScript compilation failed; see compile.log")
    require(digest(packages) == dependency_resolution["package_config_sha256"],
            "The dependency configuration changed during compilation")
    compile_receipt = {
        "version": 1, "status": "compiled", "browser_execution": "not_performed",
        "entrypoint": str(SOURCE.relative_to(ROOT)), "entrypoint_sha256": digest(SOURCE),
        "wrapper_sha256": digest(ROOT / "lib/services/office_device_export.dart"),
        "adapter_sha256": digest(ROOT / "lib/services/office_device_export_web.dart"),
        "compiled_sha256": digest(compiled),
        "dependency_resolution": dependency_resolution,
    }
    (output / "compile-receipt.json").write_text(json.dumps(compile_receipt, indent=2) + "\n")
    if args.compile_only:
        print(json.dumps(compile_receipt, indent=2))
        return
    from playwright.sync_api import sync_playwright

    (output / "index.html").write_text(
        '<!doctype html><html><head><meta charset="utf-8"><title>Office copy acceptance</title>'
        '</head><body><script src="acceptance.js"></script></body></html>'
    )
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=str(output)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    origin = f"http://127.0.0.1:{server.server_port}"
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(
                executable_path=args.chromium, headless=True,
                args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-background-networking",
                      "--disable-component-update", "--disable-default-apps", "--disable-sync",
                      "--no-first-run"],
            )
            context = browser.new_context(accept_downloads=True)
            context.route("**/*", lambda route: route.continue_()
                          if route.request.url.startswith((origin + "/", "blob:" + origin + "/"))
                          else route.abort())
            page = context.new_page()
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.add_init_script(OBSERVE)
            page.goto(origin + "/index.html", wait_until="load")
            with page.expect_download() as event:
                page.locator("#export-copy").click()
            download = event.value
            page.wait_for_function("document.querySelector('#result').dataset.complete === 'true'")
            status = json.loads(page.locator("#result").inner_text())
            require(status == {"outcome": "downloadedCopy", "caller_mutation": 127},
                    "The real service did not report the expected browser-copy outcome")
            require(download.suggested_filename == EXPECTED_NAME, "The browser filename was not sanitized")
            artifact = output / EXPECTED_NAME
            download.save_as(artifact)
            require(download.failure() is None, "The browser reported a failed download")
            require(artifact.read_bytes() == EXPECTED_BYTES,
                    "Downloaded bytes differ from the independently specified 0..255 payload")
            page.wait_for_function("window.officeCopyTrace.revoked.length === 1", timeout=5000)
            trace = page.evaluate("window.officeCopyTrace")
            require(len(trace["created"]) == len(trace["clicked"]) == len(trace["revoked"]) == 1,
                    "The copy must create, click and revoke one temporary URL")
            created, clicked, revoked = trace["created"][0], trace["clicked"][0], trace["revoked"][0]
            require(created["url"] == clicked["url"] == revoked["url"], "URL ownership mismatch")
            require(created["size"] == 256 and created["type"] == "application/octet-stream",
                    "Blob bytes or MIME type changed")
            require(clicked["name"] == EXPECTED_NAME and clicked["connected"] and clicked["display"] == "none",
                    "The download must click a connected hidden anchor with the safe name")
            anchors = page.locator("a[download]").count()
            require(anchors == 0, "The temporary download anchor was not removed")
            delay = revoked["time"] - clicked["time"]
            require(delay >= 0, "The object URL was revoked before the download click")
            revoked_in_browser = page.evaluate(
                "async url => { try { await fetch(url); return false; } catch (_) { return true; } }",
                created["url"],
            )
            require(revoked_in_browser, "The browser can still fetch the supposedly revoked object URL")
            require(not errors, "Unexpected browser script error: " + repr(errors))
            receipt = {
                "version": 1, "browser": "Chromium", "browser_version": browser.version,
                "entrypoint": str(SOURCE.relative_to(ROOT)), "entrypoint_sha256": digest(SOURCE),
                "wrapper_sha256": digest(ROOT / "lib/services/office_device_export.dart"),
                "adapter_sha256": digest(ROOT / "lib/services/office_device_export_web.dart"),
                "compiled_sha256": digest(compiled), "outcome": status["outcome"],
                "dependency_resolution": dependency_resolution,
                "filename": download.suggested_filename, "download_bytes": len(EXPECTED_BYTES),
                "download_sha256": digest(artifact), "blob_mime": created["type"],
                "anchor_connected_at_click": clicked["connected"], "remaining_download_anchors": anchors,
                "object_url_revoked": revoked_in_browser, "revocation_delay_ms": round(delay, 3),
                "page_errors": errors,
            }
            (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
            print(json.dumps(receipt, indent=2))
            context.close()
            browser.close()
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


if __name__ == "__main__":
    main()
