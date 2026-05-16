# OmnivoiceEx

[![Hex.pm](https://img.shields.io/hexpm/v/omnivoice_ex.svg)](https://hex.pm/packages/omnivoice_ex)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

Elixir wrapper for [OmniVoice](https://huggingface.co/k2-fsa/OmniVoice) — a unified speech generation model from K2-FSA.

**Voice Cloning** · **Voice Design** · **Multilingual TTS** · **Deterministic Generation** · **24kHz Output**

## Features

- 🎤 **Voice Cloning** — Clone any voice from a short reference audio clip
- 🎨 **Voice Design** — Describe a voice in natural language ("warm female broadcaster", "deep authoritative narrator")
- 🌍 **Multilingual** — Supports multiple languages with automatic detection; 646 languages available
- 🔁 **Deterministic Generation** — Stable, reproducible outputs via seed and temperature controls
- ⚡ **GPU Optimized** — CUDA, Apple Silicon (MPS), or CPU fallback
- 🔊 **24kHz WAV** — Professional-grade audio output
- 📦 **MessagePack Protocol** — Zero-base64 binary transport over Erlang Ports

## Requirements

- Elixir ≥ 1.14
- Python ≥ 3.10
- CUDA GPU (recommended), Apple Silicon MPS, or CPU
- `omnivoice` pip package (auto-installed via `mix omnivoice_ex.setup`)

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:omnivoice_ex, "~> 0.2.0"}
  ]
end
```

Then install Python dependencies:

```bash
mix omnivoice_ex.setup
```

## Quick Start

```elixir
# Start the model server
{:ok, pid} = OmnivoiceEx.start_link(device: "cuda")

# Wait for model to load
:ok = OmnivoiceEx.await_ready(pid)

# Generate speech
{:ok, audio} = OmnivoiceEx.generate(pid, "Hello, world!")

# Save to file
:ok = OmnivoiceEx.save(audio, "output.wav")

# Clean shutdown
OmnivoiceEx.stop(pid)
```

## Voice Design

Describe a voice in natural language and OmniVoice generates it:

```elixir
{:ok, audio} = OmnivoiceEx.generate(pid,
  "Welcome to our luxury resort.",
  instruct: "A warm, professional female concierge with a British accent"
)
```

## Voice Cloning

Clone a voice from a reference audio file:

```elixir
{:ok, audio} = OmnivoiceEx.generate(pid,
  "This is a cloned voice speaking English.",
  ref_audio: "/path/to/reference.wav",
  ref_text: "Transcript of the reference audio"  # optional, improves quality
)
```

## Deterministic / Reproducible Generation (v0.2.0+)

OmnivoiceEx now supports fully deterministic generation for stable outputs across runs. This is useful for:

- A/B testing prompts and settings
- CI pipelines that validate audio
- Production systems requiring consistent behavior

Key options:

- `seed`: Random seed for reproducible generation (default: 42)
- `position_temperature`: Mask-position selection temperature; 0 = greedy/deterministic (default: 0.0)
- `class_temperature`: Token sampling temperature; 0 = greedy/deterministic (default: 0.0)

Example:

```elixir
{:ok, audio} = OmnivoiceEx.generate(pid,
  "This output is fully reproducible.",
  seed: 12345,
  position_temperature: 0.0,
  class_temperature: 0.0
)
```

Under the hood (v0.2.0 fix):

- Sets `CUBLAS_WORKSPACE_CONFIG` for deterministic CuBLAS (CUDA ≥ 10.2)
- Enables `torch.backends.cudnn.deterministic = True` and best-effort `use_deterministic_algorithms(True)`
- Seeds torch, CUDA, and NumPy RNGs before each generation

## Language Selection

- `language`: OmniVoice language ID (e.g. `"zh"`, `"en"`, `"ja"`, `"ko"`, `"yue"`). Auto-detected from text if omitted. For mixed-language content, set this explicitly to avoid unstable detection.

Common IDs: `zh` (Chinese), `en` (English), `ja` (Japanese), `ko` (Korean), `yue` (Cantonese), `fr` (French), `de` (German), `es` (Spanish), `ru` (Russian), `pt` (Portuguese), `it` (Italian), `th` (Thai), `vi` (Vietnamese), `hi` (Hindi), `ar` (Arabic), `nl` (Dutch), `pl` (Polish), `sv` (Swedish), `tr` (Turkish).

Full list of 646 languages: [OmniVoice docs/languages.md](https://github.com/k2-fsa/OmniVoice/blob/master/docs/languages.md)

## Generation Options

- `ref_audio` — Path to reference audio for cloning
- `ref_text` — Transcript of reference audio (improves clone quality)
- `instruct` — Voice instruction for design (e.g. "A warm female broadcaster")
- `language` — Language ID; auto-detected if omitted
- `duration` — Target duration in seconds
- `speed` — Playback speed factor
- `num_step` — Diffusion steps (higher = better quality, slower). Default: 32
- `guidance_scale` — Classifier-free guidance. Default: 2.0
- `seed` — Random seed for reproducible generation. Default: 42
- `position_temperature` — Mask-position selection temperature; 0 = greedy/deterministic. Default: 0.0
- `class_temperature` — Token sampling temperature; 0 = greedy/deterministic. Default: 0.0

## Architecture

```
Elixir (GenServer) ←→ Erlang Port ←→ Python Bridge ←→ OmniVoice Model
                    (stdin/stdout)   (msgpack framed)
```

Uses **MessagePack** binary framing over Erlang Ports — audio is transmitted as raw WAV bytes inside msgpack, eliminating the 33% base64 overhead of JSON-based solutions.

## Changelog

### v0.2.0

- Fixed initialization bug: removed `stderr_to_stdout` from port options to avoid blocking / startup issues
- Added deterministic generation support:
  - New options: `seed`, `position_temperature`, `class_temperature`
  - CuBLAS and cuDNN determinism settings for stable GPU outputs
- Improved language documentation with common IDs and link to full list

### v0.1.0

- Initial release: Voice Cloning, Voice Design, multilingual TTS, 24kHz WAV, MessagePack protocol

## License

Apache 2.0 — see [LICENSE](LICENSE).

## Related

- [OmniVoice on HuggingFace](https://huggingface.co/k2-fsa/OmniVoice)
- [VoxCPMEx](https://hex.pm/packages/voxcpmex) — Elixir wrapper for VoxCPM2
