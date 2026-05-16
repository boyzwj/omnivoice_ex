#!/usr/bin/env python3
"""
OmniVoiceEx Bridge — Python bridge for Elixir OmniVoiceEx library.

Protocol: binary frames over stdin/stdout
  Frame: [4-byte big-endian total_length][msgpack-encoded message]

OmniVoice generates 24kHz audio. Audio is raw WAV bytes in msgpack.
"""

import sys
import io
import os
import struct
import signal

# Required for deterministic CuBLAS (CUDA >= 10.2).
# Must be set before any torch import / operation.
os.environ.setdefault("CUBLAS_WORKSPACE_CONFIG", ":4096:8")

import msgpack
import numpy as np
import soundfile as sf

# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------
_shutting_down = False

def _handle_signal(signum, frame):
    global _shutting_down
    _shutting_down = True
    sys.stderr.write(f"Bridge received signal {signum}, shutting down\n")
    sys.stderr.flush()

signal.signal(signal.SIGPIPE, signal.SIG_DFL)
signal.signal(signal.SIGTERM, _handle_signal)

# ---------------------------------------------------------------------------
# PyTorch check
# ---------------------------------------------------------------------------
try:
    import torch
except ImportError as e:
    _write_frame(msgpack.dumps({"status": "error", "error": f"Missing dependency: {e}"}))
    sys.exit(1)

_original_torch_load = torch.load

def _patched_torch_load(f, map_location=None, **kwargs):
    if map_location is None:
        map_location = "cpu"
    return _original_torch_load(f, map_location=map_location, **kwargs)

torch.load = _patched_torch_load

# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------
def _read_exact(n: int) -> bytes:
    data = b""
    while len(data) < n:
        chunk = sys.stdin.buffer.read(n - len(data))
        if not chunk:
            raise EOFError("stdin closed")
        data += chunk
    return data

def _read_frame() -> dict:
    header = _read_exact(4)
    total_len = struct.unpack(">I", header)[0]
    payload = _read_exact(total_len - 4)
    return msgpack.loads(payload, raw=False)

def _write_frame(data: bytes) -> bool:
    try:
        frame_len = struct.pack(">I", len(data) + 4)
        sys.stdout.buffer.write(frame_len + data)
        sys.stdout.buffer.flush()
        return True
    except (BrokenPipeError, OSError):
        return False

def _send(msg: dict) -> bool:
    return _write_frame(msgpack.dumps(msg))

def _send_error(error: str) -> bool:
    return _send({"status": "error", "error": error})

# ---------------------------------------------------------------------------
# Resolve device
# ---------------------------------------------------------------------------
def _resolve_device(requested: str) -> str:
    req = (requested or "cuda").strip().lower()
    if req.startswith("cuda"):
        return req if torch.cuda.is_available() else "cpu"
    if req == "mps":
        has_mps = hasattr(torch.backends, "mps") and torch.backends.mps.is_available()
        return "mps" if has_mps else "cpu"
    return "cpu"

# ---------------------------------------------------------------------------
# OmniVoice Bridge
# ---------------------------------------------------------------------------
class OmniVoiceBridge:
    def __init__(self):
        self.model = None
        self.device = None
        self.sample_rate = None

    def init_model(self, msg: dict) -> dict:
        try:
            from omnivoice import OmniVoice

            hf_model_id = msg.get("model", "k2-fsa/OmniVoice")
            dtype_str = msg.get("dtype", "float16")
            requested_device = msg.get("device", "cuda")

            self.device = _resolve_device(requested_device)
            device_map = self.device

            dtype = getattr(torch, dtype_str, torch.float16)

            sys.stderr.write(f"Loading {hf_model_id} on {device_map} ({dtype_str})...\n")
            sys.stderr.flush()

            self.model = OmniVoice.from_pretrained(
                hf_model_id,
                device_map=device_map,
                dtype=dtype,
            )

            self.sample_rate = self.model.sampling_rate or 24000
            sys.stderr.write(f"Loaded. device={self.device} sr={self.sample_rate}\n")
            sys.stderr.flush()

            return {"status": "ok", "device": self.device, "sample_rate": self.sample_rate}

        except Exception as e:
            return {"status": "error", "error": str(e)}

    def generate(self, msg: dict) -> dict:
        if self.model is None:
            return {"status": "error", "error": "Model not initialized"}

        try:
            text = msg["text"]
            gen_kwargs = {}

            # Voice cloning
            ref_audio = msg.get("ref_audio")
            ref_text = msg.get("ref_text")
            if ref_audio:
                gen_kwargs["ref_audio"] = ref_audio
                if ref_text:
                    gen_kwargs["ref_text"] = ref_text

            # Voice design
            instruct = msg.get("instruct")
            if instruct:
                gen_kwargs["instruct"] = instruct

            # Language
            language = msg.get("language")
            if language:
                gen_kwargs["language"] = language

            # Duration / speed
            duration = msg.get("duration")
            if duration:
                gen_kwargs["duration"] = duration
            speed = msg.get("speed")
            if speed:
                gen_kwargs["speed"] = speed

            # Generation config
            num_step = msg.get("num_step", 32)
            guidance_scale = msg.get("guidance_scale", 2.0)
            gen_kwargs["num_step"] = num_step
            gen_kwargs["guidance_scale"] = guidance_scale

            # Seed all RNGs for deterministic generation
            seed = msg.get("seed", 42)
            if seed is not None:
                torch.manual_seed(seed)
                torch.cuda.manual_seed_all(seed)
                np.random.seed(seed)

                # Force deterministic CUDA algorithms to eliminate GPU-level
                # non-determinism (flash attention atomics, cuDNN algorithm
                # selection, scatter ops, etc.)
                torch.backends.cudnn.deterministic = True
                torch.backends.cudnn.benchmark = False
                try:
                    torch.use_deterministic_algorithms(True)
                except Exception:
                    pass  # some ops lack deterministic impl; best effort

            # Sampling temperatures — 0 = greedy/deterministic
            gen_kwargs["position_temperature"] = msg.get("position_temperature", 0.0)
            gen_kwargs["class_temperature"] = msg.get("class_temperature", 0.0)

            audio_list = self.model.generate(text, **gen_kwargs)
            wav = audio_list[0]  # First (and usually only) output

            audio_bytes = self._wav_to_bytes(wav, self.sample_rate)

            return {
                "status": "ok",
                "audio": audio_bytes,
                "sample_rate": self.sample_rate,
                "duration": len(wav) / self.sample_rate,
            }

        except Exception as e:
            return {"status": "error", "error": str(e)}

    def _wav_to_bytes(self, wav: np.ndarray, sr: int) -> bytes:
        buf = io.BytesIO()
        if wav.dtype != np.float32:
            wav = wav.astype(np.float32)
        sf.write(buf, wav, sr, format="WAV")
        buf.seek(0)
        return buf.read()


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
def main():
    bridge = OmniVoiceBridge()

    while not _shutting_down:
        try:
            msg = _read_frame()
        except EOFError:
            sys.stderr.write("stdin closed, exiting\n")
            sys.stderr.flush()
            break
        except Exception as e:
            if not _send_error(f"Frame read error: {e}"):
                break
            continue

        msg_type = msg.get("type")

        try:
            if msg_type == "init":
                _send(bridge.init_model(msg))
            elif msg_type == "generate":
                _send(bridge.generate(msg))
            elif msg_type == "ping":
                _send({"status": "ok", "message": "pong"})
            else:
                _send_error(f"Unknown request type: {msg_type}")
        except Exception as e:
            _send_error(f"Unhandled error: {e}")


if __name__ == "__main__":
    main()
