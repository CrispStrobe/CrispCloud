#!/usr/bin/env python3
"""Regenerate the small, explicitly BT.709-tagged native video test fixture.

FFmpeg is a test-fixture authoring tool only. The application does not ship it.
RGB bars are converted to BT.709 limited-range YUV, then tagged with the same
matrix, primaries and transfer. An untagged SD clip is ambiguous: Apple can
interpret its primaries as SMPTE-C and correctly convert green to sRGB red=63,
which cannot be compared against a raw RGB primary without color management.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    parser.add_argument("--keep-video", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "test/support/media_video_fixture.dart")
    args = parser.parse_args()
    if not args.ffmpeg:
        parser.error("FFmpeg with the libx264 encoder is required")

    with tempfile.TemporaryDirectory(prefix="video_fixture_", dir=args.output.parent) as temporary:
        video = Path(temporary) / "source.mp4"
        command = [
            args.ffmpeg, "-v", "error", "-y",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "320x180", "-r", "20", "-i", "pipe:0",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=4",
            "-map", "0:v:0", "-map", "1:a:0",
            "-vf", "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p",
            "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv",
            "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-threads", "1",
            "-g", "20", "-keyint_min", "20", "-sc_threshold", "0",
            "-c:a", "aac", "-b:a", "32k", "-t", "4", "-movflags", "+faststart", str(video),
        ]
        # Four deterministic RGB quadrants. The upper-left primary changes at
        # integer seconds so spatial and temporal assertions are independent.
        frames = bytearray()
        bottom = (bytes((0, 0, 255)) * 160 + bytes((255, 0, 255)) * 160) * 90
        for primary in [(255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 255, 255)]:
            top = (bytes(primary) * 160 + bytes((255, 255, 255)) * 160) * 90
            frames.extend((top + bottom) * 20)
        subprocess.run(command, input=frames, check=True, timeout=60)
        data = video.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        encoded = "\n".join(f"  '{line}'" for line in textwrap.wrap(base64.b64encode(data).decode("ascii"), 96))
        args.output.write_text(
            "import 'dart:convert';\nimport 'dart:typed_data';\n\n"
            "// Synthetic H.264/AAC clip, generated for CrispCloud regression tests.\n"
            "// Regenerate with: python3 tool/generate_media_video_fixture.py\n"
            "// 320x180, 20 fps, four seconds; a 440 Hz audio tone.\n"
            "// BT.709 primaries/transfer/matrix, limited-range YUV420p; tags and pixels agree.\n"
            "// Upper-left color changes red -> green -> yellow -> cyan each second.\n"
            "// Other quadrants are white (upper right), blue (lower left), magenta.\n"
            "// Embedded only in the integration test, never in production app assets.\n"
            f"// SHA-256: {digest}\n"
            f"Uint8List mediaVideoFixture() => base64Decode(\n{encoded},\n);\n",
            encoding="utf-8",
        )
        if args.keep_video:
            shutil.copy2(video, args.keep_video)
        print(f"Wrote {args.output}: {len(data)} bytes, SHA-256 {digest}")


if __name__ == "__main__":
    main()
