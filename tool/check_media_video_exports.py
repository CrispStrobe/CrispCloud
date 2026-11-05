#!/usr/bin/env python3
"""Independently decode the native media integration test's retained outputs.

Usage:
  python3 tool/check_media_video_exports.py media-video-test.log \
      --output-dir artifacts/media-video

The app prints MEDIA_VIDEO_EXPORT JSON paths inside its writable sandbox. This
host-side check can read them without relaxing the application's sandbox. It
uses command-line FFmpeg only as a test oracle, never as an app dependency.
"""

from __future__ import annotations

import argparse
import array
import json
import math
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import zlib


EXPECTED = {
    "trim_crop_rotate_mute.mp4": (90, 80, 2.0, False),
    "trim_resize_audio.mp4": (160, 90, 3.0, True),
    "reopened_trim.mp4": (90, 80, 1.5, False),
    "after_cancel.mp4": (320, 180, 1.0, False),
}


def run(command: list[str]) -> bytes:
    result = subprocess.run(command, capture_output=True, check=False, timeout=60)
    if result.returncode:
        detail = result.stderr.decode("utf-8", errors="replace")[-3000:]
        raise AssertionError(f"{Path(command[0]).name} failed: {detail}")
    return result.stdout


def paths_from_log(log: Path, marker: str) -> dict[str, Path]:
    text = log.read_text(encoding="utf-8", errors="replace")
    # Flutter can repeat a progress line. Decode and de-duplicate JSON paths;
    # never interpolate an application log line into a shell command.
    matches = re.findall(re.escape(marker) + r'\s+("(?:\\.|[^"\\])*")', text)
    paths: dict[str, Path] = {}
    for match in matches:
        path = Path(json.loads(match))
        if path.name in paths and paths[path.name] != path:
            raise AssertionError(f"More than one output was reported for {path.name}")
        paths[path.name] = path
    return paths


def frame(ffmpeg: str, path: Path, seconds: float, width: int, height: int) -> bytes:
    data = run(
        [
            ffmpeg, "-v", "error", "-ss", str(seconds), "-i", str(path),
            "-map", "0:v:0", "-frames:v", "1", "-pix_fmt", "rgb24",
            "-f", "rawvideo", "pipe:1",
        ]
    )
    if len(data) != width * height * 3:
        raise AssertionError(f"Wrong decoded frame size for {path.name}: {len(data)} bytes")
    return data


def color(data: bytes, width: int, x: int, y: int, expected: tuple[int, int, int], context: str = "") -> None:
    offset = (y * width + x) * 3
    actual = tuple(data[offset : offset + 3])
    if any(abs(a - b) > 45 for a, b in zip(actual, expected)):
        raise AssertionError(f"Wrong frame color in {context} at ({x},{y}): {actual}, expected {expected}")


def sample_plan(name: str) -> list[tuple[float, list[tuple[int, int, tuple[int, int, int]]]]]:
    blue = (0, 0, 255)
    green = (0, 255, 0)
    yellow = (255, 255, 0)
    red = (255, 0, 0)
    return {
        "trim_crop_rotate_mute.mp4": [
            (0.25, [(20, 40, blue), (70, 40, green)]),
            (1.25, [(20, 40, blue), (70, 40, yellow)]),
        ],
        "trim_resize_audio.mp4": [
            (0.25, [(40, 20, red)]),
            (0.75, [(40, 20, green), (40, 70, blue)]),
        ],
        "reopened_trim.mp4": [
            (0.25, [(70, 40, green)]), (1.0, [(70, 40, yellow)]),
        ],
        "after_cancel.mp4": [(0.25, [(80, 45, green), (80, 135, blue)])],
        "source.mp4": [
            (0.25, [(80, 45, red)]),
            (1.25, [(80, 45, green), (80, 135, blue)]),
            (2.25, [(80, 45, yellow)]),
        ],
    }.get(name, [])


def check_pixels(ffmpeg: str, path: Path, width: int, height: int) -> None:
    for seconds, points in sample_plan(path.name):
        data = frame(ffmpeg, path, seconds, width, height)
        for x, y, expected in points:
            color(data, width, x, y, expected, f"{path.name} at {seconds}s")


def probe(ffprobe: str, path: Path) -> dict[str, object]:
    return json.loads(run([
        ffprobe, "-v", "error", "-count_frames", "-show_streams",
        "-show_format", "-of", "json", str(path),
    ]))


def display_size(video: dict[str, object]) -> tuple[int, int]:
    width, height = int(video["width"]), int(video["height"])
    rotations = [entry["rotation"] for entry in video.get("side_data_list", []) if "rotation" in entry]
    rotation = rotations[0] if rotations else float(video.get("tags", {}).get("rotate", 0))
    if round(rotation) % 180:
        width, height = height, width
    return width, height


def inspect_video(ffprobe: str, ffmpeg: str, path: Path) -> dict[str, object]:
    """Record evidence without asserting color, so the failing values survive."""
    metadata = probe(ffprobe, path)
    video = next(stream for stream in metadata["streams"] if stream["codec_type"] == "video")
    width, height = display_size(video)
    samples = []
    for seconds, points in sample_plan(path.name):
        data = frame(ffmpeg, path, seconds, width, height)
        for x, y, expected in points:
            offset = (y * width + x) * 3
            samples.append({
                "seconds": seconds, "x": x, "y": y,
                "rgb": list(data[offset:offset + 3]), "expected_rgb": list(expected),
            })
    return {"ffprobe": metadata, "decoded_rgb_samples": samples}


def png_color_metadata(path: Path) -> dict[str, object]:
    """Expose embedded PNG color metadata using only the standard library."""
    data = path.read_bytes()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError(f"Not a PNG thumbnail: {path.name}")
    result: dict[str, object] = {"chunks": []}
    offset = 8
    while offset + 12 <= len(data):
        size = int.from_bytes(data[offset:offset + 4], "big")
        kind = data[offset + 4:offset + 8].decode("ascii")
        value = data[offset + 8:offset + 8 + size]
        result["chunks"].append(kind)
        if kind == "gAMA" and size == 4:
            result["gamma"] = int.from_bytes(value, "big") / 100000
        elif kind == "cHRM" and size == 32:
            result["chromaticities"] = [component / 100000 for component in struct.unpack(">8I", value)]
        elif kind == "sRGB" and size == 1:
            result["srgb_rendering_intent"] = value[0]
        elif kind == "iCCP":
            profile_name, compressed = value.split(b"\0", 1)
            result["icc_profile_name"] = profile_name.decode("latin1")
            profile = zlib.decompress(compressed[1:])
            result["icc_profile_bytes"] = len(profile)
            result["icc_color_space"] = profile[16:20].decode("ascii", errors="replace")
            result["icc_connection_space"] = profile[20:24].decode("ascii", errors="replace")
        offset += 12 + size
        if kind == "IEND":
            break
    return result


def audio_tone(ffmpeg: str, path: Path) -> dict[str, float]:
    pcm = run(
        [
            ffmpeg, "-v", "error", "-i", str(path), "-map", "0:a:0",
            "-ar", "48000", "-ac", "1", "-f", "f32le", "pipe:1",
        ]
    )
    samples = array.array("f")
    samples.frombytes(pcm)
    if sys.byteorder != "little":
        samples.byteswap()
    # Avoid AAC priming / final packet padding and inspect one complete second.
    body = samples[4800:52800]
    if len(body) != 48000 or not all(math.isfinite(value) for value in body):
        raise AssertionError("Decoded audio is truncated or contains invalid samples")
    rms = math.sqrt(sum(value * value for value in body) / len(body))

    def amplitude(frequency: float) -> float:
        step = 2 * math.pi * frequency / 48000
        real = sum(value * math.cos(step * i) for i, value in enumerate(body))
        imaginary = sum(value * math.sin(step * i) for i, value in enumerate(body))
        return 2 * math.hypot(real, imaginary) / len(body)

    tone = amplitude(440)
    if not 0.03 < rms < 0.2 or not 0.06 < tone < 0.25:
        raise AssertionError(f"Retained audio lost the original tone: RMS={rms}, amplitude={tone}")
    if max(amplitude(300), amplitude(880)) > tone / 5:
        raise AssertionError("Retained audio's spectrum does not match the original 440 Hz tone")
    return {"audio_rms": rms, "audio_440_hz_amplitude": tone}


def validate(ffprobe: str, ffmpeg: str, path: Path) -> dict[str, object]:
    expected_width, expected_height, duration, has_audio = EXPECTED[path.name]
    metadata = probe(ffprobe, path)
    streams = metadata["streams"]
    videos = [stream for stream in streams if stream["codec_type"] == "video"]
    audios = [stream for stream in streams if stream["codec_type"] == "audio"]
    if len(videos) != 1 or len(audios) != int(has_audio):
        raise AssertionError(f"Unexpected stream count in {path.name}: {len(videos)} video, {len(audios)} audio")
    video = videos[0]
    width, height = display_size(video)
    if (width, height) != (expected_width, expected_height):
        raise AssertionError(f"Wrong display size for {path.name}: {width}x{height}")
    actual_duration = float(video.get("duration", metadata["format"]["duration"]))
    if abs(actual_duration - duration) > 0.1:
        raise AssertionError(f"Wrong duration for {path.name}: {actual_duration}, expected {duration}")
    frame_count = int(video["nb_read_frames"])
    if abs(frame_count - round(duration * 20)) > 1:
        raise AssertionError(f"Wrong decoded frame count for {path.name}: {frame_count}")
    # Decode every frame, independently of AVFoundation/Media3's thumbnail API.
    run([ffmpeg, "-v", "error", "-xerror", "-i", str(path), "-map", "0:v:0", "-f", "null", "-"])
    check_pixels(ffmpeg, path, width, height)
    result: dict[str, object] = {
        "name": path.name,
        "bytes": path.stat().st_size,
        "video_codec": video["codec_name"],
        "width": width,
        "height": height,
        "duration_seconds": actual_duration,
        "decoded_frames": frame_count,
        "audio_tracks": len(audios),
        "pixels_verified": True,
    }
    if has_audio:
        result.update(audio_tone(ffmpeg, path))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path, help="Full stdout from the native Flutter integration test")
    parser.add_argument("--output-dir", type=Path, help="Copy tested MP4s and a JSON report here")
    parser.add_argument("--ffprobe", default=shutil.which("ffprobe"))
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    args = parser.parse_args()
    if not args.ffprobe or not args.ffmpeg:
        parser.error("FFmpeg and ffprobe are required on the test host")
    errors: list[str] = []
    verified: list[dict[str, object]] = []
    diagnostics: dict[str, object] = {}
    failure_types = (AssertionError, KeyError, OSError, ValueError, StopIteration, subprocess.TimeoutExpired, struct.error, zlib.error)
    try:
        paths = paths_from_log(args.log, "MEDIA_VIDEO_EXPORT")
        artifacts = paths_from_log(args.log, "MEDIA_VIDEO_ARTIFACT")
        if args.output_dir:
            args.output_dir.mkdir(parents=True, exist_ok=True)
        evidence: dict[str, Path] = {}
        for name, path in {**paths, **artifacts}.items():
            try:
                allowed = name in EXPECTED or name == "source.mp4" or (
                    re.fullmatch(r'(?:source|trim_crop_rotate_mute)\.mp4\.thumb-\d+\.png', name) is not None
                )
                if not allowed:
                    raise AssertionError(f"Unexpected native diagnostic filename: {name}")
                if not path.is_absolute() or not path.is_file() or not 32 <= path.stat().st_size <= 16 * 1024 * 1024:
                    raise AssertionError(f"Native test did not retain a usable fixture/output: {path}")
                evidence[name] = path
                if args.output_dir:
                    target = args.output_dir / name
                    if path.resolve() != target.resolve():
                        shutil.copy2(path, target)
            except failure_types as error:
                errors.append(str(error))

        # Copy every available file before completeness, probe or pixel checks.
        # A failed integration test must still produce downloadable evidence.
        if set(paths) != set(EXPECTED):
            errors.append(
                f"Expected all four native exports; missing={sorted(set(EXPECTED) - set(paths))}, "
                f"unexpected={sorted(set(paths) - set(EXPECTED))}"
            )
        for name, path in evidence.items():
            try:
                diagnostics[name] = inspect_video(args.ffprobe, args.ffmpeg, path) if path.suffix == ".mp4" else png_color_metadata(path)
            except failure_types as error:
                diagnostics[name] = {"inspection_error": str(error)}
                errors.append(f"Diagnostic inspection failed for {name}: {error}")

        for name in EXPECTED:
            if name not in evidence or name not in paths:
                continue
            try:
                verified.append(validate(args.ffprobe, args.ffmpeg, evidence[name]))
            except failure_types as error:
                errors.append(f"{name}: {error}")
    except failure_types as error:
        errors.append(str(error))

    report = {"verified_native_exports": verified, "errors": errors, "diagnostics": diagnostics}
    if args.output_dir:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        (args.output_dir / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    for error in errors:
        print(f"Media video verification failed: {error}", file=sys.stderr)
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
