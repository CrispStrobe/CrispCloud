"""Expose the bundled production encoder to Flutter's browser test server."""

from pathlib import Path
import shutil


def main():
    root = Path(__file__).resolve().parents[1]
    source = root / "packages/pro_image_editor/lib/web"
    destination = root / "test/widget/assets/packages/pro_image_editor/lib/web"
    destination.mkdir(parents=True, exist_ok=True)
    for name in ("web_worker.dart.js", "web_worker.dart.js.map"):
        shutil.copyfile(source / name, destination / name)
    print("Prepared the unchanged production image worker for Chrome tests.")


if __name__ == "__main__":
    main()
