#!/usr/bin/env python3
"""Regenerate the authored binary PPT fixture using installed LibreOffice only."""

import argparse
import gzip
import os
from pathlib import Path
import signal
import subprocess
import tempfile

from pptx import Presentation
from pptx.util import Inches


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--soffice", required=True, help="Existing LibreOffice executable")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "fixtures/legacy_powerpoint/current-slides.ppt.gz")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="crisp-ppt-fixture-") as temporary:
        root = Path(temporary)
        presentation = Presentation()
        slide = presentation.slides.add_slide(presentation.slide_layouts[1])
        slide.shapes.title.text = "Current title 世界"
        slide.placeholders[1].text = "First body paragraph\nSecond body paragraph"
        box = slide.shapes.add_textbox(Inches(1), Inches(5), Inches(6), Inches(0.5))
        box.text_frame.text = "Independent shape café"
        slide.notes_slide.notes_text_frame.text = "SPEAKER NOTES MUST BE OMITTED"
        slide = presentation.slides.add_slide(presentation.slide_layouts[1])
        slide.shapes.title.text = "Second current slide"
        slide.placeholders[1].text = "Current final body"
        source = root / "current-slides.pptx"
        presentation.save(source)
        profile = root / "profile"
        (profile / "user").mkdir(parents=True)
        (profile / "user/registrymodifications.xcu").write_text(
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<oor:items xmlns:oor="http://openoffice.org/2001/registry">'
            '<item oor:path="/org.openoffice.Office.Common/Security/Scripting">'
            '<prop oor:name="DisableMacrosExecution" oor:op="fuse"><value>true</value></prop>'
            '<prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop>'
            '</item></oor:items>', encoding="utf-8"
        )
        command = [args.soffice, "-env:UserInstallation=" + profile.as_uri(),
                   "--headless", "--nologo", "--nodefault", "--norestore",
                   "--convert-to", "ppt:MS PowerPoint 97", "--outdir", str(root), str(source)]
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   env=dict(os.environ, TMPDIR=str(root)), start_new_session=os.name == "posix")
        try:
            stdout, stderr = process.communicate(timeout=45)
            if process.returncode:
                raise RuntimeError((stdout + stderr).decode("utf-8", errors="replace"))
        finally:
            if os.name == "posix":
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            elif process.poll() is None:
                process.kill()
            process.wait()
        output = root / "current-slides.ppt"
        if not output.is_file() or output.stat().st_size > 4 * 1024 * 1024:
            raise RuntimeError("LibreOffice did not produce a bounded PPT fixture")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(gzip.compress(output.read_bytes(), compresslevel=9, mtime=0))
        print(args.output)


if __name__ == "__main__":
    main()
