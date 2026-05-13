# OmnivoiceEx

[![Hex.pm](https://img.shields.io/hexpm/v/omnivoice_ex.svg)](https://hex.pm/packages/omnivoice_ex)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

Elixir wrapper for [OmniVoice](https://huggingface.co/k2-fsa/OmniVoice) — a unified speech generation model from K2-FSA.

**Voice Cloning** · **Voice Design** · **Multilingual TTS** · **24kHz Output**

## Features

- 🎤 **Voice Cloning** — Clone any voice from a short reference audio clip
- 🎨 **Voice Design** — Describe a voice in natural language ("warm female broadcaster", "deep authoritative narrator")
- 🌍 **Multilingual** — Supports multiple languages with automatic detection
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
    {:omnivoice_ex, "~> 0.1.0"}
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

## Generation Options

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `ref_audio` | `String.t()` | — | Path to reference audio for cloning |
| `ref_text` | `String.t()` | — | Transcript of reference audio |
| `instruct` | `String.t()` | — | Voice instruction for design |
| `language` | `String.t()` | — | Language code (auto-detected) |
| `duration` | `float()` | — | Target duration in seconds |
| `speed` | `float()` | — | Playback speed factor |
| `num_step` | `pos_integer()` | `32` | Diffusion steps (more = higher quality) |
| `guidance_scale` | `float()` | `2.0` | CFG guidance scale |

## Architecture

```
Elixir (GenServer) ←→ Erlang Port ←→ Python Bridge ←→ OmniVoice Model
                    (stdin/stdout)   (msgpack framed)
```

Uses **MessagePack** binary framing over Erlang Ports — audio is transmitted as raw WAV bytes inside msgpack, eliminating the 33% base64 overhead of JSON-based solutions.

## License

Apache 2.0 — see [LICENSE](LICENSE).

## Related

- [OmniVoice on HuggingFace](https://huggingface.co/k2-fsa/OmniVoice)
- [VoxCPMEx](https://hex.pm/packages/voxcpmex) — Elixir wrapper for VoxCPM2
