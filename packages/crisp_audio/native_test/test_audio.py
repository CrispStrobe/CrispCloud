#!/usr/bin/env python3
"""Compile and exercise the actual shipped audio engine with independent readers.

Run: python3 packages/crisp_audio/native_test/test_audio.py
Or:  python3 .../test_audio.py --library /absolute/path/libcrisp_audio.so

Python's wave/struct modules and FFmpeg inspect the results independently of
miniaudio. FFmpeg is test tooling only; it is not an app runtime dependency.
"""

import argparse
import ctypes
import json
import math
import os
from pathlib import Path
import shutil
import signal as signals
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import wave


OK = 0
INVALID_ARGUMENT = 1
INVALID_INPUT = 2
IO_ERROR = 4
CANCELLED = 5
OUTPUT_EXISTS = 7


class Info(ctypes.Structure):
    _fields_ = [
        ("frames", ctypes.c_uint64),
        ("sample_rate", ctypes.c_uint32),
        ("channels", ctypes.c_uint32),
    ]


class Native:
    def __init__(self, path):
        self.lib = ctypes.CDLL(str(path))
        self.lib.crisp_audio_abi_version.restype = ctypes.c_int32
        self.lib.crisp_audio_job_create.restype = ctypes.c_void_p
        self.lib.crisp_audio_job_cancel.argtypes = [ctypes.c_void_p]
        self.lib.crisp_audio_job_cancel.restype = None
        self.lib.crisp_audio_job_destroy.argtypes = [ctypes.c_void_p]
        self.lib.crisp_audio_job_destroy.restype = None
        self.lib.crisp_audio_job_progress.argtypes = [ctypes.c_void_p]
        self.lib.crisp_audio_job_progress.restype = ctypes.c_uint32
        self.lib.crisp_audio_probe.argtypes = [
            ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(Info)
        ]
        self.lib.crisp_audio_probe.restype = ctypes.c_int32
        self.lib.crisp_audio_waveform.argtypes = [
            ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_float),
            ctypes.c_uint32
        ]
        self.lib.crisp_audio_waveform.restype = ctypes.c_int32
        self.lib.crisp_audio_render.argtypes = [
            ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p,
            ctypes.c_int64, ctypes.c_int64, ctypes.c_double,
            ctypes.c_int64, ctypes.c_int64, ctypes.c_int32,
        ]
        self.lib.crisp_audio_render.restype = ctypes.c_int32

    def job(self):
        return Job(self)

    def probe(self, path):
        with self.job() as job:
            info = Info()
            status = self.lib.crisp_audio_probe(job, utf8(path), ctypes.byref(info))
            return status, info

    def render(self, source, output, start=0, end=1_000_000, gain=0,
               fade_in=0, fade_out=0, muted=False, job=None):
        if job is None:
            with self.job() as created_job:
                return self.render(source, output, start, end, gain, fade_in,
                                   fade_out, muted, created_job)
        return self.lib.crisp_audio_render(
            job, utf8(source), utf8(output), start, end, gain,
            fade_in, fade_out, int(muted)
        )


class Job:
    def __init__(self, native):
        self.native = native
        self.pointer = None

    def __enter__(self):
        self.pointer = self.native.lib.crisp_audio_job_create()
        assert self.pointer
        return self.pointer

    def __exit__(self, *_):
        self.native.lib.crisp_audio_job_destroy(self.pointer)


def utf8(path):
    return str(path).encode("utf-8")


def write_pcm(path, samples, rate=48000, channels=2):
    with wave.open(str(path), "wb") as output:
        output.setnchannels(channels)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def read_pcm(path):
    with wave.open(str(path), "rb") as source:
        params = (source.getnframes(), source.getframerate(), source.getnchannels())
        assert source.getsampwidth() == 2
        data = source.readframes(source.getnframes())
    return params, struct.unpack(f"<{len(data) // 2}h", data)


def signal(frames, channels=2, rate=48000):
    result = []
    for frame in range(frames):
        # Deliberately asymmetric channels expose accidental channel mixing.
        for channel in range(channels):
            result.append(round(12000 * math.sin(2 * math.pi *
                                                (440 + channel * 220) * frame / rate)))
    return result


class AudioContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.native = Native(LIBRARY)
        assert cls.native.lib.crisp_audio_abi_version() == 1

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="crisp-audio-test-")
        self.root = Path(self.temp.name)
        self.source = self.root / "source.wav"
        self.output = self.root / "edited.wav"
        self.samples = signal(96000)
        write_pcm(self.source, self.samples)

    def tearDown(self):
        self.temp.cleanup()

    def test_probe_and_waveform_from_real_stereo_pcm(self):
        result, info = self.native.probe(self.source)
        self.assertEqual(result, OK)
        self.assertEqual((info.frames, info.sample_rate, info.channels),
                         (96000, 48000, 2))
        count = 37  # Not a divisor of the file's frame count.
        peaks = (ctypes.c_float * count)()
        expected = [0.0] * count
        for frame in range(96000):
            index = frame * count // 96000
            expected[index] = max(expected[index],
                                  abs(self.samples[frame * 2]) / 32768,
                                  abs(self.samples[frame * 2 + 1]) / 32768)
        with self.native.job() as job:
            result = self.native.lib.crisp_audio_waveform(
                job, utf8(self.source), peaks, count
            )
            self.assertEqual(result, OK)
            self.assertEqual(self.native.lib.crisp_audio_job_progress(job), 1_000_000)
        for actual, wanted in zip(peaks, expected):
            self.assertAlmostEqual(actual, wanted, places=6)

    def test_trim_is_sample_accurate_and_preserves_both_channels(self):
        before = self.source.read_bytes()
        result = self.native.render(self.source, self.output,
                                    start=250_000, end=1_250_000)
        self.assertEqual(result, OK)
        params, samples = read_pcm(self.output)
        self.assertEqual(params, (48000, 48000, 2))
        self.assertEqual(samples, tuple(self.samples[12000 * 2:60000 * 2]))
        self.assertEqual(self.source.read_bytes(), before)
        result, info = self.native.probe(self.output)
        self.assertEqual(result, OK)
        self.assertEqual(info.frames, 48000)

    def test_gain_and_fades_match_an_independent_sample_calculation(self):
        gain_db = -6
        result = self.native.render(self.source, self.output,
                                    start=250_000, end=1_250_000, gain=gain_db,
                                    fade_in=200_000, fade_out=300_000)
        self.assertEqual(result, OK)
        params, samples = read_pcm(self.output)
        self.assertEqual(params, (48000, 48000, 2))
        self.assertEqual(samples[:2], (0, 0))
        self.assertEqual(samples[-2:], (0, 0))
        base_gain = 10 ** (gain_db / 20)
        for frame in range(0, 48000, 97):
            fade = 1.0
            if frame < 9600:
                fade *= frame / (9600 - 1)
            if 48000 - frame <= 14400:
                fade *= (48000 - frame - 1) / (14400 - 1)
            for channel in range(2):
                wanted = round(self.samples[(12000 + frame) * 2 + channel]
                               * base_gain * fade)
                self.assertLessEqual(abs(samples[frame * 2 + channel] - wanted), 1)

    def test_overlapping_fades_and_gain_clipping_are_defined(self):
        mono = self.root / "constant.wav"
        write_pcm(mono, [24000] * 8000, rate=8000, channels=1)
        result = self.native.render(mono, self.output, gain=12,
                                    fade_in=800_000, fade_out=800_000)
        self.assertEqual(result, OK)
        _, samples = read_pcm(self.output)
        self.assertEqual(samples[0], 0)
        self.assertEqual(samples[-1], 0)
        self.assertEqual(max(samples), 32767)
        for frame in (100, 1500, 4000, 7000):
            fade = min(1, frame / 6399) * min(1, (7999 - frame) / 6399)
            wanted = min(32767, round(24000 * 10 ** (12 / 20) * fade))
            self.assertLessEqual(abs(samples[frame] - wanted), 1)

    def test_muted_export_is_silent_with_the_selected_duration(self):
        self.assertEqual(self.native.render(self.source, self.output,
                                           start=500_000, end=750_000,
                                           muted=True), OK)
        params, samples = read_pcm(self.output)
        self.assertEqual(params, (12000, 48000, 2))
        self.assertEqual(set(samples), {0})

    def test_full_44100_hz_selection_keeps_the_final_fractional_sample(self):
        source = self.root / "fraction.wav"
        samples = signal(44101, channels=1, rate=44100)
        samples[-1] = 12345
        write_pcm(source, samples, rate=44100, channels=1)
        result, info = self.native.probe(source)
        self.assertEqual(result, OK)
        duration = (info.frames * 1_000_000 + info.sample_rate - 1) // info.sample_rate
        self.assertEqual(self.native.render(source, self.output, end=duration), OK)
        params, exported = read_pcm(self.output)
        self.assertEqual(params, (44101, 44100, 1))
        self.assertEqual(exported, tuple(samples))

    def test_existing_destination_and_source_are_never_overwritten(self):
        sentinel = b"a user's existing file"
        self.output.write_bytes(sentinel)
        self.assertEqual(self.native.render(self.source, self.output), OUTPUT_EXISTS)
        self.assertEqual(self.output.read_bytes(), sentinel)
        before = self.source.read_bytes()
        self.assertEqual(self.native.render(self.source, self.source), OUTPUT_EXISTS)
        self.assertEqual(self.source.read_bytes(), before)

    def test_unicode_paths(self):
        directory = self.root / "Stimme_ä_日本語"
        directory.mkdir()
        source = directory / "Música.wav"
        source.write_bytes(self.source.read_bytes())
        output = directory / "声_edit.wav"
        self.assertEqual(self.native.render(source, output), OK)
        self.assertEqual(read_pcm(output)[0], (48000, 48000, 2))

    def test_invalid_edits_fail_without_creating_an_output(self):
        for kwargs in (
            {"start": -1}, {"start": 1_000_000}, {"end": 2_500_000},
            {"gain": float("nan")}, {"gain": float("inf")}, {"gain": 25},
            {"fade_in": -1}, {"fade_out": 1_000_001}, {"end": 1},
        ):
            with self.subTest(kwargs=kwargs):
                self.assertEqual(self.native.render(self.source, self.output, **kwargs),
                                 INVALID_ARGUMENT)
                self.assertFalse(self.output.exists())

    def test_corrupt_inputs_and_io_failure_are_not_success(self):
        corrupt = self.root / "bad.wav"
        corrupt.write_bytes(b"not audio data")
        self.assertEqual(self.native.probe(corrupt)[0], INVALID_INPUT)
        self.assertEqual(self.native.render(corrupt, self.output), INVALID_INPUT)
        self.assertFalse(self.output.exists())
        self.assertEqual(self.native.render(self.source, self.root / "missing" / "out.wav"),
                         IO_ERROR)

    def test_truncated_input_removes_output_after_rendering_has_started(self):
        # The header still declares two seconds. The decoder can open the file,
        # but export must discover the short read and remove the partial WAV.
        self.source.write_bytes(self.source.read_bytes()[:-100])
        self.assertEqual(self.native.probe(self.source)[0], OK)
        self.assertEqual(self.native.render(self.source, self.output, end=2_000_000),
                         INVALID_INPUT)
        self.assertFalse(self.output.exists())

    @unittest.skipIf(sys.platform == "win32", "POSIX file size limit fixture")
    def test_write_failure_is_reported_and_partial_output_removed(self):
        import resource
        old_limit = resource.getrlimit(resource.RLIMIT_FSIZE)
        old_handler = signals.signal(signals.SIGXFSZ, signals.SIG_IGN)
        try:
            resource.setrlimit(resource.RLIMIT_FSIZE, (32768, old_limit[1]))
            result = self.native.render(self.source, self.output)
        finally:
            resource.setrlimit(resource.RLIMIT_FSIZE, old_limit)
            signals.signal(signals.SIGXFSZ, old_handler)
        self.assertEqual(result, IO_ERROR)
        self.assertFalse(self.output.exists())

    def test_multichannel_is_rejected_until_speaker_layout_is_supported(self):
        surround = self.root / "surround.wav"
        write_pcm(surround, [1000] * 8000 * 6, rate=8000, channels=6)
        self.assertEqual(self.native.probe(surround)[0], 3)
        self.assertEqual(self.native.render(surround, self.output), 3)
        self.assertFalse(self.output.exists())

    def test_declared_duration_and_pcm_size_overflow_are_rejected_before_writing(self):
        # Tiny malformed fixtures advertise large 8-bit PCM streams. Metadata
        # inspection must impose duration/output-size limits before decoding or
        # allocating anything proportional to their declared frame counts.
        for rate, frames, too_long in ((8000, 1_000_000_000, True),
                                      (192000, 2_200_000_000, False)):
            with self.subTest(rate=rate, frames=frames):
                source = self.root / f"declared-{rate}.wav"
                header = struct.pack("<4sI4s4sIHHIIHH4sI",
                                     b"RIFF", frames + 36, b"WAVE", b"fmt ",
                                     16, 1, 1, rate, rate, 1, 8, b"data", frames)
                source.write_bytes(header + b"\x80")
                result, info = self.native.probe(source)
                if too_long:
                    self.assertEqual(result, 3)
                else:
                    self.assertEqual(result, OK)
                    self.assertEqual(info.frames, frames)
                    end = (frames * 1_000_000 + rate - 1) // rate
                    self.assertEqual(self.native.render(source, self.output, end=end), 3)
                self.assertFalse(self.output.exists())

    def test_cancel_before_export_and_during_work_removes_only_partial_output(self):
        with self.native.job() as job:
            self.native.lib.crisp_audio_job_cancel(job)
            self.assertEqual(self.native.render(self.source, self.output, job=job), CANCELLED)
            self.assertFalse(self.output.exists())
        # Write a long file in fixed-size chunks, so the fixture itself does not
        # mask an accidental whole-file allocation in the implementation.
        long_source = self.root / "long.wav"
        with wave.open(str(long_source), "wb") as source:
            source.setnchannels(2)
            source.setsampwidth(2)
            source.setframerate(48000)
            second = struct.pack("<hh", 12000, -6000) * 48000
            for _ in range(300):
                source.writeframesraw(second)
        with self.native.job() as job:
            results = []
            thread = threading.Thread(target=lambda: results.append(
                self.native.render(long_source, self.output, end=300_000_000, job=job)
            ))
            thread.start()
            deadline = time.monotonic() + 10
            while self.native.lib.crisp_audio_job_progress(job) == 0 and thread.is_alive():
                self.assertLess(time.monotonic(), deadline)
                time.sleep(0.0005)
            self.native.lib.crisp_audio_job_cancel(job)
            thread.join(timeout=10)
            self.assertFalse(thread.is_alive())
            self.assertEqual(results, [CANCELLED])
            self.assertFalse(self.output.exists())
        self.assertEqual(self.native.probe(long_source)[1].frames, 300 * 48000)
        # Retry after cancellation uses a new job and succeeds.
        self.assertEqual(self.native.render(self.source, self.output), OK)

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"),
                         "FFmpeg/ffprobe required for independent codec verification")
    def test_flac_and_mp3_decoding_and_ffprobe_export_inspection(self):
        for extension, codec in (("flac", "flac"), ("mp3", "libmp3lame")):
            with self.subTest(codec=codec):
                source = self.root / f"compressed.{extension}"
                output = self.root / f"from-{extension}.wav"
                subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-i",
                                str(self.source), "-c:a", codec, str(source)], check=True)
                result, info = self.native.probe(source)
                self.assertEqual(result, OK)
                self.assertEqual((info.sample_rate, info.channels), (48000, 2))
                self.assertAlmostEqual(info.frames / info.sample_rate, 2, delta=0.1)
                self.assertEqual(self.native.render(source, output,
                                                   start=250_000, end=1_250_000), OK)
                params, samples = read_pcm(output)
                self.assertEqual(params, (48000, 48000, 2))
                self.assertGreater(sum(value * value for value in samples) / len(samples),
                                   10_000_000)
                if extension == "flac":
                    self.assertEqual(samples, tuple(self.samples[12000 * 2:60000 * 2]))
                probe = json.loads(subprocess.check_output([
                    "ffprobe", "-v", "error", "-show_entries",
                    "stream=codec_name,sample_rate,channels,bits_per_sample,duration",
                    "-of", "json", str(output)
                ]))
                stream = probe["streams"][0]
                self.assertEqual(stream["codec_name"], "pcm_s16le")
                self.assertEqual(stream["sample_rate"], "48000")
                self.assertEqual(stream["channels"], 2)
                self.assertEqual(stream["bits_per_sample"], 16)
                self.assertAlmostEqual(float(stream["duration"]), 1, places=6)



    @unittest.skipUnless(shutil.which("ffmpeg"), "FFmpeg required to author a FLAC fixture")
    def test_id3_prefixed_flac_probes_waveforms_and_seeks_without_modifying_source(self):
        plain = self.root / "plain.flac"
        subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-i", str(self.source),
                        "-c:a", "flac", str(plain)], check=True)
        audio = plain.read_bytes()
        for version, footer in ((2, False), (3, False), (4, False), (4, True)):
            with self.subTest(version=version, footer=footer):
                payload = b"TIT2" + b"metadata" * 541
                length = len(payload)
                header = b"ID3" + bytes((version, 0, 16 if footer else 0)) + bytes(
                    (length >> shift) & 127 for shift in (21, 14, 7, 0))
                original = header + payload + (b"3DI" + header[3:] if footer else b"") + audio
                source = self.root / f"tagged-v{version}-{footer}.flac"
                source.write_bytes(original)
                result, info = self.native.probe(source)
                self.assertEqual(result, OK)
                self.assertEqual((info.frames, info.sample_rate, info.channels), (96000, 48000, 2))
                peaks = (ctypes.c_float * 37)()
                with self.native.job() as job:
                    self.assertEqual(self.native.lib.crisp_audio_waveform(job, utf8(source), peaks, 37), OK)
                self.assertGreater(max(peaks), 0.3)
                output = self.root / f"tagged-v{version}-{footer}.wav"
                self.assertEqual(self.native.render(source, output, start=250_000, end=1_250_000), OK)
                params, samples = read_pcm(output)
                self.assertEqual(params, (48000, 48000, 2))
                self.assertEqual(samples, tuple(self.samples[12000 * 2:60000 * 2]))
                self.assertEqual(source.read_bytes(), original)


    def test_malformed_id3_prefix_is_rejected_without_creating_output(self):
        for header in (b"ID3\x03\x00\x00\x80\x00\x00\x00",
                       b"ID3\x04\x00\x10\x7f\x7f\x7f\x7f",
                       b"ID3\x03\x00\x00\x00\x00\x01\x00"):
            source = self.root / "invalid.flac"
            original = header + b"fLaC"
            source.write_bytes(original)
            self.assertEqual(self.native.probe(source)[0], INVALID_INPUT)
            self.assertNotEqual(self.native.render(source, self.output), OK)
            self.assertFalse(self.output.exists())
            self.assertEqual(source.read_bytes(), original)


def build_library(directory):
    source = Path(__file__).resolve().parents[1] / "src" / "crisp_audio.cpp"
    if sys.platform == "darwin":
        library = directory / "libcrisp_audio.dylib"
        shared_flag = "-dynamiclib"
    elif sys.platform == "win32":
        raise SystemExit("On Windows pass --library <built crisp_audio.dll>.")
    else:
        library = directory / "libcrisp_audio.so"
        shared_flag = "-shared"
    compiler = os.environ.get("CXX") or shutil.which("g++") or shutil.which("clang++")
    if not compiler:
        raise SystemExit("A C++17 compiler is required; install g++ or clang++.")
    subprocess.run([compiler, "-std=c++17", "-O2", "-fPIC", "-fvisibility=hidden",
                    "-D_FILE_OFFSET_BITS=64", shared_flag, str(source),
                    "-o", str(library), "-lm"], check=True)
    return library


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path)
    options, remaining = parser.parse_known_args()
    with tempfile.TemporaryDirectory(prefix="crisp-audio-build-") as build:
        LIBRARY = options.library.resolve() if options.library else build_library(Path(build))
        unittest.main(argv=[sys.argv[0], *remaining], verbosity=2)
