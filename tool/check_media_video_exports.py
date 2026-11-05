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
import subprocess
import sys


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


def exports_from_log(log: Path) -> dict[str, Path]:
    text = log.read_text(encoding="utf-8", errors="replace")
    # Flutter can repeat a progress line. Decode and de-duplicate JSON paths;
    # never interpolate an application log line into a shell command.
    matches = re.findall(r'MEDIA_VIDEO_EXPORT\s+("(?:\\.|[^"\\])*")', text)
    paths: dict[str, Path] = {}
    for match in matches:
        path = Path(json.loads(match))
        if path.name in paths and paths[path.name] != path:
            raise AssertionError(f"More than one output was reported for {path.name}")
        paths[path.name] = path
    if set(paths) != set(EXPECTED):
        raise AssertionError(
            f"Expected all four native exports; missing={set(EXPECTED) - set(paths)}, "
            f"unexpected={set(paths) - set(EXPECTED)}"
        )
    for path in paths.values():
        if not path.is_absolute() or not path.is_file() or path.stat().st_size < 32:
            raise AssertionError(f"Native test did not retain a usable output: {path}")
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


def color(data: bytes, width: int, x: int, y: int, expected: tuple[int, int, int]) -> None:
    offset = (y * width + x) * 3
    actual = tuple(data[offset : offset + 3])
    if any(abs(a - b) > 45 for a, b in zip(actual, expected)):
        raise AssertionError(f"Wrong frame color at ({x},{y}): {actual}, expected {expected}")


def check_pixels(ffmpeg: str, path: Path, width: int, height: int) -> None:
    blue = (0, 0, 255)
    green = (0, 255, 0)
    yellow = (255, 255, 0)
    red = (255, 0, 0)
    if path.name == "trim_crop_rotate_mute.mp4":
        first = frame(ffmpeg, path, 0.25, width, height)
        second = frame(ffmpeg, path, 1.25, width, height)
        color(first, width, 20, 40, blue)
        color(first, width, 70, 40, green)
        color(second, width, 20, 40, blue)
        color(second, width, 70, 40, yellow)
    elif path.name == "trim_resize_audio.mp4":
        first = frame(ffmpeg, path, 0.25, width, height)
        second = frame(ffmpeg, path, 0.75, width, height)
        color(first, width, 40, 20, red)
        color(second, width, 40, 20, green)
        color(second, width, 40, 70, blue)
    elif path.name == "reopened_trim.mp4":
        first = frame(ffmpeg, path, 0.25, width, height)
        second = frame(ffmpeg, path, 1.0, width, height)
        color(first, width, 70, 40, green)
        color(second, width, 70, 40, yellow)
    elif path.name == "after_cancel.mp4":
        first = frame(ffmpeg, path, 0.25, width, height)
        color(first, width, 80, 45, green)
        color(first, width, 80, 135, blue)


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
    metadata = json.loads(
        run(
            [
                ffprobe, "-v", "error", "-count_frames", "-show_streams",
                "-show_format", "-of", "json", str(path),
            ]
        )
    )
    streams = metadata["streams"]
    videos = [stream for stream in streams if stream["codec_type"] == "video"]
    audios = [stream for stream in streams if stream["codec_type"] == "audio"]
    if len(videos) != 1 or len(audios) != int(has_audio):
        raise AssertionError(f"Unexpected stream count in {path.name}: {len(videos)} video, {len(audios)} audio")
    video = videos[0]
    width, height = int(video["width"]), int(video["height"])
    rotations = [entry["rotation"] for entry in video.get("side_data_list", []) if "rotation" in entry]
    rotation = rotations[0] if rotations else float(video.get("tags", {}).get("rotate", 0))
    if round(rotation) % 180:
        width, height = height, width
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
    try:
        paths = exports_from_log(args.log)
        report = [validate(args.ffprobe, args.ffmpeg, paths[name]) for name in EXPECTED]
        if args.output_dir:
            args.output_dir.mkdir(parents=True, exist_ok=True)
            for path in paths.values():
                shutil.copy2(path, args.output_dir / path.name)
            (args.output_dir / "report.json").write_text(
                json.dumps(report, indent=2) + "\n", encoding="utf-8"
            )
        print(json.dumps({"verified_native_exports": report}, indent=2))
        return 0
    except (AssertionError, KeyError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"Media video verification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
