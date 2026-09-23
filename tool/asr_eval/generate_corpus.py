#!/usr/bin/env python3
"""Generates the device-free voice-evaluation audio corpus for Tasuke AI.

Every case with at least one task in the five extraction corpora
(test/fixtures/nl/extraction_{dev,fresh,heldout,complex_dev,complex_heldout}
_corpus.json) is spoken by Piper TTS voices, then degraded in controlled ways
(speed, white/pink/babble noise, low gain, long leading/trailing silence).
The result is a directory of 16 kHz mono PCM16 WAVs and a manifest.json that
test/asr/asr_eval_test.dart feeds through the app's real whisper.cpp
recognizer and rule-based extractor.

The whole flow, from the repo root (Python with piper-tts, onnxruntime and
numpy; the host library needs gcc/g++ and make):

    tool/asr_eval/build_host_whisper.sh /path/to/hostwhisper
    <venv>/bin/python tool/asr_eval/generate_corpus.py \\
        --out /path/to/asr_corpus --voices-dir /path/to/piper_voices
    . tool/env.sh
    LD_LIBRARY_PATH=/path/to/hostwhisper \\
    TASUKE_ASR_MANIFEST=/path/to/asr_corpus/manifest.json \\
    TASUKE_ASR_OUT=/path/to/results.json \\
        flutter test test/asr/asr_eval_test.dart --tags asr

What it produces (under --out):

    manifest.json     [{id, wav, condition, voice, text, now, tasks,
                        source_corpus, ...}] one entry per clip
    corpus_info.json  settings, voices (model sha256, sample rate, measured
                      pitch), sentence list and subset, per-condition counts
    wav/<condition>/<condition>_<voice>_<case>.wav

Clip ids are ``condition_voice_caseid``; none of the three parts contains an
underscore, so ``id.split('_')`` always yields exactly those three.

Case ids are ``<corpus tag>-<index>``, where index is the 0-based position
of the case in that corpus file's "cases" array (cases without tasks are
skipped but keep their index slot), e.g. ``cxdev-012``. Each clip keeps its
corpus file's "now" and the case's task labels unchanged.

Conditions (the voice rotation is described at ``plan_clips``):

    clean      every sentence x 3 rotating voices
    fast       the 40-sentence subset, Piper length_scale x0.8 (speech
               about x0.88 as long: see verify_corpus)
    slow       the subset, Piper length_scale x1.25 (about x1.15)
    white20/10/5, pink20/10/5
               the subset, white or pink noise at that SNR (dB)
    babble10   the subset, the sum of 3 other TTS utterances at SNR 10 dB
    quiet      the subset, clean clip at -20 dB gain
    padded     the subset, 1.5 s lead + 2 s tail silence under a -60 dBFS
               white noise floor (tap the mic, wait, then speak)

With the 242 labelled cases that is 726 clean + 11 x 40 = 1,166 clips.
``--tempo-scope all`` puts fast and slow on every sentence instead (one voice
each, 1,570 clips). The subset is drawn per corpus in proportion to its size.

A subset sentence is spoken by the same voice in all eleven degraded
conditions, and that voice is one of its three clean voices, so every
degraded clip has a clean clip of the same case and voice
(``clean_<voice>_<case>``) to be compared with; noise, gain and padding
clips reuse that clean clip's speech sample for sample.

Levels: each synthesized utterance is normalized to an active speech level of
-26 dBFS (mean power of the 20 ms frames within 35 dB of the loudest frame;
a simplified ITU-T P.56), capped at a -1 dBFS peak. Clean, tempo and noise
clips carry 0.3 s of lead and tail; SNRs are active speech level over the
noise's level (whole-clip RMS for white/pink, active level for babble).
After mixing, a clip whose peak would exceed -0.2 dBFS is scaled down as a
whole (SNR unchanged) and the applied gain is recorded in the manifest.

Determinism: onnxruntime's RandomNormalLike (Piper's VITS noise) draws from
a generator seeded when the session is created and advanced on every run.
So each utterance gets its own session, created right after
onnxruntime.set_seed(<crc32 of seed, voice, case, length scale>), with one
intra-op thread: the same inputs give bit-identical WAVs on the same machine
regardless of worker count or job order. Noise uses numpy's PCG64 seeded per
clip. Resampling (Piper's 22.05 kHz to 16 kHz) is a Kaiser-windowed sinc
polyphase filter implemented below and self-tested on every run.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import ctypes
import dataclasses
import hashlib
import json
import math
import multiprocessing
import os
import random
import re
import shutil
import statistics
import sys
import time
import wave
import zlib
from pathlib import Path
from typing import Any, Optional

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "test" / "fixtures" / "nl"

SAMPLE_RATE = 16000
DEFAULT_SEED = 20260923

# (tag used in case ids, fixture file stem). Order fixes case order.
CORPORA: list[tuple[str, str]] = [
    ("dev", "extraction_dev_corpus"),
    ("fresh", "extraction_fresh_corpus"),
    ("heldout", "extraction_heldout_corpus"),
    ("cxdev", "extraction_complex_dev_corpus"),
    ("cxheld", "extraction_complex_heldout_corpus"),
]


# --------------------------------------------------------------------------
# Voices


@dataclasses.dataclass(frozen=True)
class VoiceSpec:
    tag: str  # short id used in clip ids: no underscores
    model: str  # Piper voice name, e.g. en_US-lessac-medium
    speaker: Optional[str]  # key in speaker_id_map for multi-speaker models
    gender: str
    accent: str


# Eight single-speaker voices: US and GB, female and male.
PRIMARY_VOICES: list[VoiceSpec] = [
    VoiceSpec("us-lessac", "en_US-lessac-medium", None, "female", "US"),
    VoiceSpec("us-amy", "en_US-amy-medium", None, "female", "US"),
    VoiceSpec("us-ryan", "en_US-ryan-medium", None, "male", "US"),
    VoiceSpec("us-joe", "en_US-joe-medium", None, "male", "US"),
    VoiceSpec("us-kristin", "en_US-kristin-medium", None, "female", "US"),
    VoiceSpec("gb-alan", "en_GB-alan-medium", None, "male", "GB"),
    VoiceSpec("gb-northernmale", "en_GB-northern_english_male-medium", None, "male", "GB"),
    VoiceSpec("gb-southernfemale", "en_GB-southern_english_female-low", None, "female", "GB"),
]

# When a primary voice cannot be downloaded, the first remaining substitute
# of the same gender takes its place (any gender if none is left), so the
# female/male balance survives a flaky network.
SUBSTITUTE_VOICES: list[VoiceSpec] = [
    VoiceSpec("gb-jenny", "en_GB-jenny_dioco-medium", None, "female", "GB"),
    VoiceSpec("us-hfcmale", "en_US-hfc_male-medium", None, "male", "US"),
    VoiceSpec("gb-cori", "en_GB-cori-medium", None, "female", "GB"),
    VoiceSpec("us-john", "en_US-john-medium", None, "male", "US"),
    VoiceSpec("us-hfcfemale", "en_US-hfc_female-medium", None, "female", "US"),
    VoiceSpec("us-bryce", "en_US-bryce-medium", None, "male", "US"),
]


# --------------------------------------------------------------------------
# Conditions


@dataclasses.dataclass(frozen=True)
class Condition:
    name: str
    group: str  # clean | tempo | noise | level | padding
    scope: str  # all | subset
    length_factor: float = 1.0  # multiplies the voice's own length_scale
    noise: Optional[str] = None  # white | pink | babble
    snr_db: Optional[float] = None
    gain_db: float = 0.0
    lead_s: float = 0.3
    tail_s: float = 0.3
    floor_dbfs: Optional[float] = None  # white noise floor under the clip


CONDITIONS: list[Condition] = [
    Condition("clean", "clean", "all"),
    Condition("fast", "tempo", "subset", length_factor=0.8),
    Condition("slow", "tempo", "subset", length_factor=1.25),
    Condition("white20", "noise", "subset", noise="white", snr_db=20.0),
    Condition("white10", "noise", "subset", noise="white", snr_db=10.0),
    Condition("white5", "noise", "subset", noise="white", snr_db=5.0),
    Condition("pink20", "noise", "subset", noise="pink", snr_db=20.0),
    Condition("pink10", "noise", "subset", noise="pink", snr_db=10.0),
    Condition("pink5", "noise", "subset", noise="pink", snr_db=5.0),
    Condition("babble10", "noise", "subset", noise="babble", snr_db=10.0),
    Condition("quiet", "level", "subset", gain_db=-20.0),
    Condition("padded", "padding", "subset", lead_s=1.5, tail_s=2.0, floor_dbfs=-60.0),
]
CONDITION_BY_NAME = {c.name: c for c in CONDITIONS}

CLEAN_VOICES_PER_SENTENCE = 3
BABBLE_TALKERS = 3
SENTENCE_GAP_S = 0.3  # silence between Piper's per-sentence chunks
BABBLE_GAP_S = 0.15  # between repeats of one babble talker
TARGET_ACTIVE_DBFS = -26.0
UTTERANCE_PEAK_DBFS = -1.0
CLIP_PEAK_DBFS = -0.2
ACTIVE_FRAME_S = 0.02
ACTIVE_REL_DB = -35.0


# --------------------------------------------------------------------------
# Signal helpers


def db_to_amp(db: float) -> float:
    return 10.0 ** (db / 20.0)


def amp_to_db(a: float) -> float:
    return 20.0 * math.log10(max(a, 1e-12))


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(x, dtype=np.float64)))) if len(x) else 0.0


def active_rms(x: np.ndarray, sr: int = SAMPLE_RATE) -> float:
    """RMS over the 20 ms frames within 35 dB of the loudest frame."""
    frame = int(sr * ACTIVE_FRAME_S)
    n = len(x) // frame * frame
    if n == 0:
        return rms(x)
    energy = np.mean(np.square(x[:n].reshape(-1, frame), dtype=np.float64), axis=1)
    peak = float(energy.max())
    if peak <= 0:
        return 0.0
    active = energy >= peak * 10.0 ** (ACTIVE_REL_DB / 10.0)
    return float(np.sqrt(energy[active].mean()))


def _kaiser(u: np.ndarray, beta: float) -> np.ndarray:
    out = np.zeros_like(u)
    inside = np.abs(u) <= 1.0
    out[inside] = np.i0(beta * np.sqrt(1.0 - u[inside] ** 2)) / np.i0(beta)
    return out


_RESAMPLE_FILTERS: dict[tuple[int, int], tuple[np.ndarray, int]] = {}


def resample(x: np.ndarray, sr_in: int, sr_out: int) -> np.ndarray:
    """Anti-aliased rational resampling (Kaiser-windowed sinc, polyphase).

    Cutoff at 0.96 x the lower Nyquist, 64 zero crossings per side, Kaiser
    beta 8 (about 80 dB stopband). For 22050 -> 16000 Hz: flat to ~7.3 kHz,
    stopband from ~7.95 kHz, so nothing above 8 kHz aliases back.
    """
    x = np.asarray(x, dtype=np.float64)
    if sr_in == sr_out:
        return x.copy()
    g = math.gcd(sr_in, sr_out)
    up, down = sr_out // g, sr_in // g
    key = (up, down)
    if key not in _RESAMPLE_FILTERS:
        fc = 0.96 * min(1.0, up / down)  # cutoff, as a fraction of input Nyquist
        half = 64 / fc  # window half-width in input samples
        taps_half = int(math.ceil(half))
        phase = np.arange(up)[:, None] / up
        j = np.arange(-taps_half + 1, taps_half + 1)[None, :]
        tau = phase - j  # output time minus input sample time
        h = fc * np.sinc(fc * tau) * _kaiser(tau / half, 8.0)
        h /= h.sum(axis=1, keepdims=True)  # unity DC gain on every phase
        _RESAMPLE_FILTERS[key] = (h, taps_half)
    h, taps_half = _RESAMPLE_FILTERS[key]
    n_out = (len(x) * up + down - 1) // down
    n = np.arange(n_out, dtype=np.int64)
    base = (n * down) // up
    ph = (n * down) % up
    padded = np.pad(x, (taps_half, taps_half + 1))
    windows = np.lib.stride_tricks.sliding_window_view(padded, 2 * taps_half)
    y = np.empty(n_out, dtype=np.float64)
    step = 8192
    for s in range(0, n_out, step):
        e = min(n_out, s + step)
        y[s:e] = np.einsum("ij,ij->i", windows[base[s:e] + 1], h[ph[s:e]])
    return y


def resampler_self_test() -> list[str]:
    """Checks passband accuracy and alias rejection for 22050 -> 16000 Hz."""
    problems: list[str] = []
    sr_in = 22050
    t_in = np.arange(sr_in * 2) / sr_in
    edge = 400  # ignore filter start-up at both ends

    def run(freq: float) -> tuple[np.ndarray, np.ndarray]:
        y = resample(np.sin(2 * np.pi * freq * t_in), sr_in, SAMPLE_RATE)
        ideal = np.sin(2 * np.pi * freq * np.arange(len(y)) / SAMPLE_RATE)
        return y[edge:-edge], ideal[edge:-edge]

    for freq in (440.0, 1000.0, 3000.0):
        y, ideal = run(freq)
        err_db = amp_to_db(rms(y - ideal) / rms(ideal))
        if err_db > -60:
            problems.append(f"{freq:.0f} Hz reconstruction error {err_db:.1f} dB (want < -60)")
    y, ideal = run(7000.0)
    gain_db = amp_to_db(rms(y) / rms(ideal))
    if abs(gain_db) > 0.1:
        problems.append(f"7 kHz passband gain {gain_db:+.2f} dB (want within 0.1 dB)")
    for freq in (8300.0, 9500.0, 10500.0):
        y, _ = run(freq)
        leak_db = amp_to_db(rms(y) / math.sqrt(0.5))
        if leak_db > -60:
            problems.append(f"{freq:.0f} Hz alias leak {leak_db:.1f} dB (want < -60)")
    return problems


def white_noise(n: int, rng: np.random.Generator) -> np.ndarray:
    return rng.standard_normal(n)


def pink_noise(n: int, rng: np.random.Generator) -> np.ndarray:
    """1/f power (-3 dB/octave) from 20 Hz up, unit RMS."""
    spec = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1.0 / SAMPLE_RATE)
    shape = 1.0 / np.sqrt(np.maximum(freqs, 20.0))
    shape[0] = 0.0
    p = np.fft.irfft(spec * shape, n)
    return p / rms(p)


def to_pcm16(x: np.ndarray) -> np.ndarray:
    return np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")


def write_wav(path: Path, pcm: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm.tobytes())


def read_wav(path: Path) -> tuple[np.ndarray, dict[str, int]]:
    with wave.open(str(path), "rb") as w:
        info = {
            "channels": w.getnchannels(),
            "sampwidth": w.getsampwidth(),
            "rate": w.getframerate(),
            "frames": w.getnframes(),
        }
        data = w.readframes(w.getnframes())
    return np.frombuffer(data, dtype="<i2").astype(np.float64) / 32767.0, info


def seed_of(*parts: object) -> int:
    """A stable 31-bit seed (crc32; Python's hash() is salted per process)."""
    return zlib.crc32("|".join(str(p) for p in parts).encode("utf-8")) & 0x7FFFFFFF


def estimate_f0(x: np.ndarray, sr: int = SAMPLE_RATE) -> Optional[float]:
    """Median autocorrelation pitch (60-400 Hz) over voiced 40 ms frames."""
    frame, hop = int(0.04 * sr), int(0.02 * sr)
    lo, hi = int(sr / 400), int(sr / 60)
    level = active_rms(x, sr)
    pitches = []
    for s in range(0, len(x) - frame, hop):
        f = x[s : s + frame] - np.mean(x[s : s + frame])
        if rms(f) < level * 0.5:
            continue
        ac = np.correlate(f, f, "full")[frame - 1 :]
        if ac[0] <= 0:
            continue
        lag = lo + int(np.argmax(ac[lo:hi]))
        if ac[lag] / ac[0] > 0.5:
            pitches.append(sr / lag)
    return float(statistics.median(pitches)) if pitches else None


# --------------------------------------------------------------------------
# Sentences


@dataclasses.dataclass
class Sentence:
    case_id: str
    text: str
    now: str
    tasks: list[dict[str, Optional[str]]]
    source_corpus: str
    profile: Optional[str]


def load_sentences() -> list[Sentence]:
    sentences: list[Sentence] = []
    for tag, stem in CORPORA:
        doc = json.loads((FIXTURES / f"{stem}.json").read_text(encoding="utf-8"))
        now = doc.get("now") or "2026-09-21T10:00"
        for index, case in enumerate(doc["cases"]):
            if not case.get("tasks"):
                continue
            sentences.append(
                Sentence(
                    case_id=f"{tag}-{index:03d}",
                    text=case["note"].strip(),
                    now=now,
                    tasks=[
                        {"title": t["title"], "date": t.get("date"), "time": t.get("time")}
                        for t in case["tasks"]
                    ],
                    source_corpus=stem,
                    profile=case.get("profile"),
                )
            )
    return sentences


def pick_subset(sentences: list[Sentence], size: int, seed: int) -> list[str]:
    """``size`` sentences drawn per corpus in proportion to its size
    (largest-remainder quotas), with a seeded RNG; returned in corpus order."""
    if size >= len(sentences):
        return [s.case_id for s in sentences]
    by_corpus: dict[str, list[str]] = {}
    for s in sentences:
        by_corpus.setdefault(s.source_corpus, []).append(s.case_id)
    corpus_order = [c for _, c in CORPORA]
    total = len(sentences)
    quotas = {k: size * len(v) / total for k, v in by_corpus.items()}
    counts = {k: int(math.floor(q)) for k, q in quotas.items()}
    # Largest remainder, ties broken by corpus order.
    order = sorted(quotas, key=lambda k: (-(quotas[k] - counts[k]), corpus_order.index(k)))
    for k in order[: size - sum(counts.values())]:
        counts[k] += 1
    rng = random.Random(seed)
    chosen: set[str] = set()
    for stem in corpus_order:
        if stem in by_corpus:
            chosen.update(rng.sample(by_corpus[stem], counts[stem]))
    return [s.case_id for s in sentences if s.case_id in chosen]


# --------------------------------------------------------------------------
# Voice download and validation


def _voice_files(voices_dir: Path, model: str) -> tuple[Path, Path]:
    return voices_dir / f"{model}.onnx", voices_dir / f"{model}.onnx.json"


def _voice_is_valid(voices_dir: Path, model: str) -> bool:
    import onnxruntime

    onnx_path, cfg_path = _voice_files(voices_dir, model)
    if not onnx_path.exists() or not cfg_path.exists():
        return False
    try:
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
        if int(cfg["audio"]["sample_rate"]) <= 0:
            return False
        so = onnxruntime.SessionOptions()
        so.intra_op_num_threads = 1
        onnxruntime.InferenceSession(str(onnx_path), so, providers=["CPUExecutionProvider"])
        return True
    except Exception:  # truncated download, bad JSON, ...
        return False


def ensure_voice(voices_dir: Path, model: str, attempts: int, offline: bool) -> bool:
    """Downloads (with retries) and validates one Piper voice."""
    from piper.download_voices import download_voice

    voices_dir.mkdir(parents=True, exist_ok=True)
    if _voice_is_valid(voices_dir, model):
        return True
    if offline:
        return False
    for attempt in range(1, attempts + 1):
        for p in _voice_files(voices_dir, model):
            p.unlink(missing_ok=True)
        try:
            download_voice(model, voices_dir)
        except Exception as error:  # network flakiness
            print(f"  download {model} attempt {attempt}/{attempts} failed: {error}", flush=True)
        if _voice_is_valid(voices_dir, model):
            return True
        time.sleep(min(30, 2**attempt))
    for p in _voice_files(voices_dir, model):
        p.unlink(missing_ok=True)
    return False


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def resolve_voices(voices_dir: Path, attempts: int, offline: bool) -> list[VoiceSpec]:
    """The eight primary voices, each replaced by a substitute (same gender
    first) when it cannot be downloaded. Fails rather than run with fewer."""
    voices: list[VoiceSpec] = []
    substitutes = list(SUBSTITUTE_VOICES)
    for spec in PRIMARY_VOICES:
        chosen: Optional[VoiceSpec] = None
        if ensure_voice(voices_dir, spec.model, attempts, offline):
            chosen = spec
        else:
            print(f"  voice {spec.model} unavailable, substituting", flush=True)
            candidates = [s for s in substitutes if s.gender == spec.gender]
            candidates += [s for s in substitutes if s.gender != spec.gender]
            for sub in candidates:
                substitutes.remove(sub)
                if ensure_voice(voices_dir, sub.model, attempts, offline):
                    chosen = sub
                    break
        if chosen is None:
            raise SystemExit(f"no voice available for {spec.model} and no substitutes left")
        voices.append(chosen)
    return voices


# --------------------------------------------------------------------------
# Synthesis (runs in worker processes)

_WORKER_CONFIGS: dict[str, Any] = {}


def synthesize_job(job: dict[str, Any]) -> tuple[str, np.ndarray, int]:
    """Synthesizes one utterance; returns (key, 16 kHz float32 audio, native rate).

    A fresh onnxruntime session per utterance, created right after set_seed,
    makes the VITS noise depend on this job's seed alone.
    """
    import onnxruntime
    from piper import PiperVoice, SynthesisConfig
    from piper.config import PiperConfig

    model_path = job["model_path"]
    if model_path not in _WORKER_CONFIGS:
        cfg_dict = json.loads(Path(model_path + ".json").read_text(encoding="utf-8"))
        _WORKER_CONFIGS[model_path] = (PiperConfig.from_dict(cfg_dict), cfg_dict)
    config, cfg_dict = _WORKER_CONFIGS[model_path]
    speaker_id = None
    if job["speaker"] is not None:
        speaker_id = int(cfg_dict["speaker_id_map"][job["speaker"]])

    onnxruntime.set_seed(int(job["seed"]))
    so = onnxruntime.SessionOptions()
    so.intra_op_num_threads = 1
    so.inter_op_num_threads = 1
    session = onnxruntime.InferenceSession(model_path, so, providers=["CPUExecutionProvider"])
    voice = PiperVoice(config=config, session=session)
    syn = SynthesisConfig(
        speaker_id=speaker_id,
        length_scale=config.length_scale * job["length_factor"],
        normalize_audio=True,
    )
    sr = config.sample_rate
    gap = np.zeros(int(round(SENTENCE_GAP_S * sr)), dtype=np.float32)
    parts: list[np.ndarray] = []
    for chunk in voice.synthesize(job["text"], syn_config=syn):
        if parts:
            parts.append(gap)
        parts.append(chunk.audio_float_array.astype(np.float32))
    if not parts:
        raise RuntimeError(f"Piper produced no audio for {job['key']}")
    audio = resample(np.concatenate(parts), sr, SAMPLE_RATE)
    level = active_rms(audio)
    if level <= 0:
        raise RuntimeError(f"silent synthesis for {job['key']}")
    audio *= db_to_amp(TARGET_ACTIVE_DBFS) / level
    peak = float(np.max(np.abs(audio)))
    if peak > db_to_amp(UTTERANCE_PEAK_DBFS):
        audio *= db_to_amp(UTTERANCE_PEAK_DBFS) / peak
    return job["key"], audio.astype(np.float32), sr


# --------------------------------------------------------------------------
# Planning


@dataclasses.dataclass
class Clip:
    condition: Condition
    sentence: Sentence
    voice: VoiceSpec
    utterance: str  # key of the synthesized utterance it is built from

    @property
    def clip_id(self) -> str:
        return f"{self.condition.name}_{self.voice.tag}_{self.sentence.case_id}"


def utterance_key(voice: VoiceSpec, case_id: str, length_factor: float) -> str:
    return f"{voice.tag}|{case_id}|{length_factor:g}"


def assign_clean_voices(sentences: list[Sentence], voices: list[VoiceSpec]) -> dict[str, list[VoiceSpec]]:
    """Sentence i gets voices (3i+k) mod V, k = 0..2: distinct, evenly rotated."""
    n = len(voices)
    return {
        s.case_id: [voices[(CLEAN_VOICES_PER_SENTENCE * i + k) % n] for k in range(CLEAN_VOICES_PER_SENTENCE)]
        for i, s in enumerate(sentences)
    }


def plan_clips(
    sentences: list[Sentence],
    voices: list[VoiceSpec],
    subset: list[str],
    conditions: list[Condition],
) -> list[Clip]:
    """Voice rotation.

    Sentence i (in corpus order) is spoken clean by voices (3i+k) mod V for
    k = 0, 1, 2, so the voices rotate evenly over the sentence list. A subset
    sentence uses one of its clean voices in every subset condition: taken in
    subset (corpus) order, the one given to the fewest subset sentences so
    far (lowest k on a tie), which spreads the subset evenly over the voices.
    With ``--tempo-scope all``, sentence i's fast clip uses its clean voice
    k = i mod 3 and its slow clip k = (i+1) mod 3.
    """
    clean_voices = assign_clean_voices(sentences, voices)
    by_id = {s.case_id: s for s in sentences}
    subset_voice: dict[str, VoiceSpec] = {}
    used: dict[str, int] = {v.tag: 0 for v in voices}
    for case_id in subset:
        v = min(clean_voices[case_id], key=lambda c: used[c.tag])  # first minimum
        subset_voice[case_id] = v
        used[v.tag] += 1
    clips: list[Clip] = []
    for cond in conditions:
        if cond.scope == "all":
            for i, s in enumerate(sentences):
                if cond.group == "clean":
                    chosen = clean_voices[s.case_id]
                elif cond.name == "fast":
                    chosen = [clean_voices[s.case_id][i % CLEAN_VOICES_PER_SENTENCE]]
                else:
                    chosen = [clean_voices[s.case_id][(i + 1) % CLEAN_VOICES_PER_SENTENCE]]
                for v in chosen:
                    clips.append(Clip(cond, s, v, utterance_key(v, s.case_id, cond.length_factor)))
        else:
            for case_id in subset:
                v = subset_voice[case_id]
                clips.append(Clip(cond, by_id[case_id], v, utterance_key(v, case_id, cond.length_factor)))
    return clips


def babble_sources(
    clip: Clip, sentences: list[Sentence], clean_voices: dict[str, list[VoiceSpec]], seed: int
) -> list[tuple[str, str]]:
    """Three other sentences, each by a clean voice distinct from the target's
    and from each other. Returns [(case_id, voice_tag)]."""
    rng = random.Random(seed_of(seed, "babble", clip.clip_id))
    order = [s for s in sentences if s.text != clip.sentence.text]
    rng.shuffle(order)
    used = {clip.voice.tag}
    out: list[tuple[str, str]] = []
    for s in order:
        options = [v for v in clean_voices[s.case_id] if v.tag not in used]
        if not options:
            continue
        v = rng.choice(options)
        used.add(v.tag)
        out.append((s.case_id, v.tag))
        if len(out) == BABBLE_TALKERS:
            break
    return out


# --------------------------------------------------------------------------
# Rendering one clip


def render_clip(
    clip: Clip,
    core: np.ndarray,
    utterances: dict[str, np.ndarray],
    babble: list[tuple[str, str]],
    seed: int,
) -> tuple[np.ndarray, dict[str, Any]]:
    cond = clip.condition
    lead = int(round(cond.lead_s * SAMPLE_RATE))
    tail = int(round(cond.tail_s * SAMPLE_RATE))
    speech = np.concatenate([np.zeros(lead), core.astype(np.float64), np.zeros(tail)])
    total = len(speech)
    params: dict[str, Any] = {
        "length_factor": cond.length_factor,
        "lead_s": cond.lead_s,
        "tail_s": cond.tail_s,
        "speech_active_dbfs": round(amp_to_db(active_rms(core)), 2),
    }
    rng = np.random.default_rng(seed_of(seed, "noise", clip.clip_id))
    mix = speech * db_to_amp(cond.gain_db)
    if cond.gain_db:
        params["gain_db"] = cond.gain_db
    if cond.noise is not None:
        if cond.noise == "white":
            noise = white_noise(total, rng)
            noise_level = rms(noise)
        elif cond.noise == "pink":
            noise = pink_noise(total, rng)
            noise_level = rms(noise)
        else:
            noise = np.zeros(total)
            for case_id, voice_tag in babble:
                src = utterances[f"{voice_tag}|{case_id}|1"].astype(np.float64)
                unit = np.concatenate([src, np.zeros(int(BABBLE_GAP_S * SAMPLE_RATE))])
                reps = int(math.ceil((total + len(unit)) / len(unit)))
                looped = np.tile(unit, reps)
                offset = int(rng.integers(0, len(unit)))
                noise += looped[offset : offset + total]
            noise_level = active_rms(noise)
            params["babble_sources"] = [f"{v}_{c}" for c, v in babble]
        target_noise = active_rms(core) * db_to_amp(-cond.snr_db)
        mix = mix + noise * (target_noise / noise_level)
        params["noise"] = cond.noise
        params["snr_db"] = cond.snr_db
    if cond.floor_dbfs is not None:
        floor = white_noise(total, rng)
        mix = mix + floor * (db_to_amp(cond.floor_dbfs) / rms(floor))
        params["floor_dbfs"] = cond.floor_dbfs
    peak = float(np.max(np.abs(mix)))
    protect_db = 0.0
    if peak > db_to_amp(CLIP_PEAK_DBFS):
        protect = db_to_amp(CLIP_PEAK_DBFS) / peak
        mix = mix * protect
        protect_db = amp_to_db(protect)
    params["clip_protect_db"] = round(protect_db, 3)
    return mix, params


# --------------------------------------------------------------------------
# Verification


def verify_corpus(manifest: list[dict[str, Any]]) -> list[str]:
    """Re-reads every WAV and checks format, level, and each degradation
    against its clean pair. Returns a list of problems (empty = pass)."""
    problems: list[str] = []
    cache: dict[str, np.ndarray] = {}

    def load(entry: dict[str, Any]) -> np.ndarray:
        if entry["id"] not in cache:
            x, info = read_wav(Path(entry["wav"]))
            if (info["channels"], info["sampwidth"], info["rate"]) != (1, 2, SAMPLE_RATE):
                problems.append(f"{entry['id']}: format {info}")
            cache[entry["id"]] = x
        return cache[entry["id"]]

    by_id = {e["id"]: e for e in manifest}
    tempo_ratio: dict[str, list[float]] = {"fast": [], "slow": []}
    for e in manifest:
        x = load(e)
        dur = len(x) / SAMPLE_RATE
        if abs(dur - e["duration_s"]) > 1e-3:
            problems.append(f"{e['id']}: duration {dur:.3f} != manifest {e['duration_s']}")
        if dur < 0.5:
            problems.append(f"{e['id']}: too short ({dur:.2f} s)")
        if np.max(np.abs(x)) >= 32767 / 32767.0:
            problems.append(f"{e['id']}: touches full scale")
        if amp_to_db(active_rms(x)) < -55:
            problems.append(f"{e['id']}: nearly silent ({amp_to_db(active_rms(x)):.1f} dBFS active)")
        cond = CONDITION_BY_NAME[e["condition"]]
        if cond.name == "clean":
            continue
        clean_id = f"clean_{e['voice']}_{e['case_id']}"
        if clean_id not in by_id:
            problems.append(f"{e['id']}: no clean pair {clean_id}")
            continue
        c = load(by_id[clean_id])
        pad = int(round(0.3 * SAMPLE_RATE))
        clean_core = c[pad : len(c) - pad]
        if cond.group == "tempo":
            core_len = len(x) - 2 * pad
            tempo_ratio[cond.name].append(core_len / len(clean_core))
            continue
        lead = int(round(cond.lead_s * SAMPLE_RATE))
        core = x[lead : lead + len(clean_core)]
        if len(x) != lead + len(clean_core) + int(round(cond.tail_s * SAMPLE_RATE)):
            problems.append(f"{e['id']}: length does not match clean pair plus padding")
            continue
        undo = db_to_amp(-e["params"]["clip_protect_db"])
        if cond.noise is not None:
            residual = x * undo
            residual[lead : lead + len(clean_core)] -= clean_core
            if cond.noise == "babble":
                measured = amp_to_db(active_rms(clean_core) / active_rms(residual))
            else:
                measured = amp_to_db(active_rms(clean_core) / rms(residual))
            e["params"]["measured_snr_db"] = round(measured, 2)
            if abs(measured - cond.snr_db) > 0.25:
                problems.append(f"{e['id']}: measured SNR {measured:.2f} dB, want {cond.snr_db}")
        elif cond.group == "level":
            measured = amp_to_db(rms(core * undo) / rms(clean_core))
            e["params"]["measured_gain_db"] = round(measured, 2)
            if abs(measured - cond.gain_db) > 0.1:
                problems.append(f"{e['id']}: measured gain {measured:.2f} dB, want {cond.gain_db}")
        elif cond.group == "padding":
            floor_lead = amp_to_db(rms(x[: lead - SAMPLE_RATE // 10]))
            floor_tail = amp_to_db(rms(x[len(x) - int(cond.tail_s * SAMPLE_RATE) + SAMPLE_RATE // 10 :]))
            residual_db = amp_to_db(rms(core - clean_core))
            e["params"]["measured_floor_dbfs"] = round(floor_lead, 2)
            for name, val in (("lead floor", floor_lead), ("tail floor", floor_tail), ("floor under speech", residual_db)):
                if abs(val - cond.floor_dbfs) > 1.0:
                    problems.append(f"{e['id']}: {name} {val:.1f} dBFS, want {cond.floor_dbfs}")
    # Piper's length_scale scales each phoneme's predicted duration, which
    # VITS then rounds UP to whole frames, and Piper puts a pad token between
    # phonemes; the rounding does not scale, so x0.8 / x1.25 shorten /
    # lengthen the speech by about x0.88 / x1.15 (median over 248 sentences:
    # 0.876 and 1.154). The bounds catch a length_scale that did nothing.
    for name, want_lo, want_hi in (("fast", 0.80, 0.95), ("slow", 1.08, 1.30)):
        if tempo_ratio[name]:
            med = statistics.median(tempo_ratio[name])
            print(f"  {name}: median speech duration vs its clean pair x{med:.3f} (n={len(tempo_ratio[name])})")
            if not want_lo <= med <= want_hi:
                problems.append(f"{name}: median duration ratio {med:.3f} outside [{want_lo}, {want_hi}]")
    return problems


# --------------------------------------------------------------------------
# Optional ASR spot-check through the app's own native whisper library


_WORD = re.compile(r"[a-z0-9']+")


def _norm_words(text: str) -> list[str]:
    """Rough WER normalisation for the spot-check (the Dart harness has the
    full one): a.m./p.m. in any spelling to am/pm split off its digit,
    "3:00"/"3.00" to 3, "3:30"/"3.30"/"330 pm" to 3 30, ordinals to digits."""
    t = text.lower()
    t = re.sub(r"(?<![a-z])([ap])\s?\.\s?m\b\.?", r" \1m ", t)
    t = re.sub(r"(\d)\s*([ap]m)\b", r"\1 \2", t)
    t = re.sub(r"\b(\d{1,2})([0-5]\d) ([ap]m)\b", r"\1 \2 \3", t)  # "740 pm"
    t = re.sub(r"\b(\d{1,2})[:.]00\b", r"\1", t)
    t = re.sub(r"\b(\d{1,2})[:.](\d{2})\b", r"\1 \2", t)
    t = re.sub(r"\b(\d+)(st|nd|rd|th)\b", r"\1", t)
    return _WORD.findall(t)


def word_error_rate(ref: str, hyp: str) -> float:
    r, h = _norm_words(ref), _norm_words(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)] / max(1, len(r))


def asr_spot_check(manifest: list[dict[str, Any]], lib_path: Path, model_path: Path, per_condition: int) -> None:
    """Transcribes a few clips per condition with libwhisper_ggml's request()
    (the batch getTextFromWavFile path, not the app's streaming path)."""
    lib = ctypes.CDLL(str(lib_path))
    lib.request.argtypes = [ctypes.c_char_p]
    lib.request.restype = ctypes.c_void_p
    picked: list[dict[str, Any]] = []
    for cond in CONDITIONS:
        picked.extend([e for e in manifest if e["condition"] == cond.name][:per_condition])
    print(f"\nASR spot-check ({lib_path.name}, {model_path.name}):")
    for e in picked:
        body = {
            "@type": "getTextFromWavFile",
            "threads": 4,
            "is_verbose": False,
            "is_translate": False,
            "language": "en",
            "is_special_tokens": False,
            "is_no_timestamps": True,
            "model": str(model_path),
            "audio": e["wav"],
            "split_on_word": False,
            "diarize": False,
            "keep_model_loaded": True,
        }
        ptr = lib.request(json.dumps(body).encode("utf-8"))
        out = json.loads(ctypes.string_at(ptr).decode("utf-8", "replace"))
        text = (out.get("text") or out.get("message") or "").strip()
        wer = word_error_rate(e["text"], text)
        print(f"  {e['id']:<40} WER {wer:5.1%}  {text}")
    lib.request(json.dumps({"@type": "releaseModel"}).encode("utf-8"))


# --------------------------------------------------------------------------
# Main


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", type=Path, required=True, help="corpus output directory")
    ap.add_argument("--voices-dir", type=Path, required=True, help="Piper voice cache (downloaded into)")
    ap.add_argument("--seed", type=int, default=DEFAULT_SEED)
    ap.add_argument("--subset-size", type=int, default=40)
    ap.add_argument(
        "--tempo-scope",
        choices=["subset", "all"],
        default="subset",
        help="fast/slow on the subset (default) or on every sentence (+404 clips)",
    )
    ap.add_argument("--workers", type=int, default=max(1, min(12, (os.cpu_count() or 2) - 2)))
    ap.add_argument("--download-attempts", type=int, default=6)
    ap.add_argument("--offline", action="store_true", help="never download; use what --voices-dir has")
    ap.add_argument("--asr-check-lib", type=Path, help="libwhisper_ggml.so for an optional ASR spot-check")
    ap.add_argument("--asr-check-model", type=Path, default=REPO_ROOT / "assets/models/ggml-base.en-q5_1.bin")
    ap.add_argument("--asr-check-per-condition", type=int, default=1)
    args = ap.parse_args()

    try:
        import onnxruntime
        import piper
    except ImportError as error:
        raise SystemExit(f"run this with a Python that has piper-tts and onnxruntime ({error})")

    t_start = time.time()
    problems = resampler_self_test()
    if problems:
        raise SystemExit("resampler self-test failed:\n  " + "\n  ".join(problems))
    print("resampler self-test passed (22050 -> 16000 Hz: passband error < -60 dB, alias leak < -60 dB)")

    out: Path = args.out.resolve()
    voices_dir: Path = args.voices_dir.resolve()
    sentences = load_sentences()
    subset = pick_subset(sentences, args.subset_size, seed_of(args.seed, "subset"))
    per_source: dict[str, int] = {}
    for s in sentences:
        per_source[s.source_corpus] = per_source.get(s.source_corpus, 0) + 1
    print(f"sentences: {len(sentences)} " + ", ".join(f"{k} {v}" for k, v in per_source.items()))
    subset_sources: dict[str, int] = {}
    for s in sentences:
        if s.case_id in subset:
            subset_sources[s.source_corpus] = subset_sources.get(s.source_corpus, 0) + 1
    print(f"subset: {len(subset)} sentences " + ", ".join(f"{k} {v}" for k, v in subset_sources.items()))
    conditions = [
        dataclasses.replace(c, scope="all") if c.group == "tempo" and args.tempo_scope == "all" else c
        for c in CONDITIONS
    ]

    print("voices:")
    voices = resolve_voices(voices_dir, args.download_attempts, args.offline)
    for v in voices:
        print(f"  {v.tag:<20} {v.model} ({v.gender}, {v.accent})")

    clips = plan_clips(sentences, voices, subset, conditions)
    clean_voices = assign_clean_voices(sentences, voices)
    voice_by_tag = {v.tag: v for v in voices}

    # Every distinct utterance, synthesized once.
    jobs: dict[str, dict[str, Any]] = {}
    for clip in clips:
        if clip.utterance in jobs:
            continue
        v = clip.voice
        factor = clip.condition.length_factor
        jobs[clip.utterance] = {
            "key": clip.utterance,
            "model_path": str(_voice_files(voices_dir, v.model)[0]),
            "speaker": v.speaker,
            "text": clip.sentence.text,
            "length_factor": factor,
            "seed": seed_of(args.seed, "tts", v.tag, clip.sentence.case_id, f"{factor:g}"),
        }
    babble_plan: dict[str, list[tuple[str, str]]] = {}
    for clip in clips:
        if clip.condition.noise == "babble":
            babble_plan[clip.clip_id] = babble_sources(clip, sentences, clean_voices, args.seed)
            for case_id, tag in babble_plan[clip.clip_id]:
                key = utterance_key(voice_by_tag[tag], case_id, 1.0)
                assert key in jobs, key  # every clean utterance is already planned

    print(f"synthesizing {len(jobs)} utterances with {args.workers} workers ...", flush=True)
    utterances: dict[str, np.ndarray] = {}
    native_rates: dict[str, int] = {}
    t0 = time.time()
    ctx = multiprocessing.get_context("spawn")
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers, mp_context=ctx) as pool:
        ordered = sorted(jobs.values(), key=lambda j: (j["model_path"], j["key"]))
        for i, (key, audio, sr) in enumerate(pool.map(synthesize_job, ordered, chunksize=4), start=1):
            utterances[key] = audio
            native_rates[key.split("|")[0]] = sr
            if i % 100 == 0 or i == len(ordered):
                print(f"  {i}/{len(ordered)} ({time.time() - t0:.0f} s)", flush=True)

    # Fresh output: only the paths this tool owns.
    shutil.rmtree(out / "wav", ignore_errors=True)
    for name in ("manifest.json", "corpus_info.json"):
        (out / name).unlink(missing_ok=True)
    out.mkdir(parents=True, exist_ok=True)

    manifest: list[dict[str, Any]] = []
    for clip in clips:
        core = utterances[clip.utterance]
        mix, params = render_clip(clip, core, utterances, babble_plan.get(clip.clip_id, []), args.seed)
        pcm = to_pcm16(mix)
        wav_path = out / "wav" / clip.condition.name / f"{clip.clip_id}.wav"
        write_wav(wav_path, pcm)
        x = pcm.astype(np.float64) / 32767.0
        manifest.append(
            {
                "id": clip.clip_id,
                "wav": str(wav_path),
                "condition": clip.condition.name,
                "voice": clip.voice.tag,
                "text": clip.sentence.text,
                "now": clip.sentence.now,
                "tasks": clip.sentence.tasks,
                "source_corpus": clip.sentence.source_corpus,
                "case_id": clip.sentence.case_id,
                # The clean clip of the same case and voice (null on clean clips).
                "clean_pair": None
                if clip.condition.group == "clean"
                else f"clean_{clip.voice.tag}_{clip.sentence.case_id}",
                "profile": clip.sentence.profile,
                "condition_group": clip.condition.group,
                "voice_model": clip.voice.model,
                "voice_speaker": clip.voice.speaker,
                "voice_gender": clip.voice.gender,
                "voice_accent": clip.voice.accent,
                "duration_s": round(len(pcm) / SAMPLE_RATE, 4),
                "rms_dbfs": round(amp_to_db(rms(x)), 2),
                "active_dbfs": round(amp_to_db(active_rms(x)), 2),
                "peak_dbfs": round(amp_to_db(float(np.max(np.abs(x)))), 2),
                "tts_seed": jobs[clip.utterance]["seed"],
                "params": params,
            }
        )

    by_id = {e["id"]: e for e in manifest}
    print("verifying every WAV against its clean pair ...", flush=True)
    problems = verify_corpus(manifest)

    (out / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")

    counts: dict[str, int] = {}
    for e in manifest:
        counts[e["condition"]] = counts.get(e["condition"], 0) + 1
    voice_counts: dict[str, int] = {}
    for e in manifest:
        voice_counts[e["voice"]] = voice_counts.get(e["voice"], 0) + 1
    voice_info = []
    for v in voices:
        onnx_path, cfg_path = _voice_files(voices_dir, v.model)
        own = sorted(k for k in utterances if k.startswith(v.tag + "|") and k.endswith("|1"))[:10]
        f0s = [f for f in (estimate_f0(utterances[k]) for k in own) if f]
        voice_info.append(
            {
                **dataclasses.asdict(v),
                "native_sample_rate": native_rates.get(v.tag),
                "model_sha256": sha256_of(onnx_path),
                "config_sha256": sha256_of(cfg_path),
                "median_f0_hz": round(statistics.median(f0s), 1) if f0s else None,
                "clips": voice_counts.get(v.tag, 0),
            }
        )
    info = {
        "generator": "tool/asr_eval/generate_corpus.py",
        "seed": args.seed,
        "sample_rate": SAMPLE_RATE,
        "format": "WAV, mono, PCM 16-bit little-endian",
        "levels": {
            "target_active_dbfs": TARGET_ACTIVE_DBFS,
            "utterance_peak_cap_dbfs": UTTERANCE_PEAK_DBFS,
            "clip_peak_cap_dbfs": CLIP_PEAK_DBFS,
            "active_level": f"{int(ACTIVE_FRAME_S * 1000)} ms frames within {-ACTIVE_REL_DB:g} dB of the loudest",
        },
        "piper_tts": getattr(piper, "__version__", None) or _dist_version("piper-tts"),
        "onnxruntime": onnxruntime.__version__,
        "numpy": np.__version__,
        "tempo_scope": args.tempo_scope,
        "conditions": [dataclasses.asdict(c) for c in conditions],
        "counts": counts,
        "total_clips": len(manifest),
        "voices": voice_info,
        "subset": subset,
        "sentences": [dataclasses.asdict(s) for s in sentences],
        "verification_problems": problems,
    }
    (out / "corpus_info.json").write_text(json.dumps(info, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")

    print("\nclips per condition:")
    for cond in CONDITIONS:
        durs = [e["duration_s"] for e in manifest if e["condition"] == cond.name]
        rmss = [e["rms_dbfs"] for e in manifest if e["condition"] == cond.name]
        print(
            f"  {cond.name:<9} {counts.get(cond.name, 0):>5}   duration {min(durs):5.2f}-{max(durs):5.2f} s"
            f" (mean {statistics.mean(durs):5.2f})   RMS mean {statistics.mean(rmss):6.1f} dBFS"
        )
    print(f"  {'total':<9} {len(manifest):>5}")
    print("clips per voice: " + ", ".join(f"{k} {v}" for k, v in voice_counts.items()))

    print("\nspot-check (read back from disk):")
    # One case and voice through every condition: the first subset sentence
    # (its clean clip is the pair of all its degraded ones).
    first = next(e for e in manifest if e["condition"] == "white20")
    spot = [by_id[f"{c.name}_{first['voice']}_{first['case_id']}"] for c in CONDITIONS]
    for e in spot:
        x, fmt = read_wav(Path(e["wav"]))
        extra = ""
        p = e["params"]
        if "measured_snr_db" in p:
            extra = f"  SNR {p['measured_snr_db']:.2f} dB"
        elif "measured_gain_db" in p:
            extra = f"  gain {p['measured_gain_db']:.2f} dB"
        elif "measured_floor_dbfs" in p:
            extra = f"  floor {p['measured_floor_dbfs']:.1f} dBFS"
        print(
            f"  {e['id']:<40} {fmt['rate']} Hz {fmt['channels']}ch {8 * fmt['sampwidth']}bit"
            f"  {len(x) / SAMPLE_RATE:5.2f} s  RMS {amp_to_db(rms(x)):6.1f} dBFS"
            f"  active {amp_to_db(active_rms(x)):6.1f}  peak {amp_to_db(float(np.max(np.abs(x)))):5.1f}{extra}"
        )

    if args.asr_check_lib:
        asr_spot_check(manifest, args.asr_check_lib.resolve(), args.asr_check_model.resolve(), args.asr_check_per_condition)

    print(f"\nmanifest: {out / 'manifest.json'}")
    print(f"info:     {out / 'corpus_info.json'}")
    print(f"done in {time.time() - t_start:.0f} s")
    if problems:
        print(f"\nVERIFICATION FAILED ({len(problems)} problems):")
        for p in problems[:50]:
            print("  " + p)
        return 1
    print("verification passed: formats, durations, levels, SNRs, gains and padding all match")
    return 0


def _dist_version(name: str) -> Optional[str]:
    try:
        from importlib.metadata import version

        return version(name)
    except Exception:
        return None


if __name__ == "__main__":
    sys.exit(main())
