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

## Production & Engineering

This section provides practical guidance for using OmnivoiceEx in real systems: concurrency, reliability, monitoring, and common pitfalls.

### Concurrency and Request Handling

- The Python bridge is a single process behind one GenServer. Generation calls are executed serially inside the model; concurrent `generate/3` requests are queued internally.
- Recommended patterns:
  - Use a **single server per node** in most cases:
    - Start once at application startup, share it via a named GenServer or Supervisor.
  - For high-load clusters:
    - Run one OmnivoiceEx instance per GPU (or per model replica).
    - Distribute requests across nodes using a load balancer or job queue.

Example: named server in supervision tree

```elixir
defmodule MyApp.OmniVoiceSupervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      {OmnivoiceEx,
       name: OmniVoiceServer,
       device: System.get_env("OMNIVOICE_DEVICE") || "cuda",
       model: System.get_env("OMNIVOICE_MODEL") || "k2-fsa/OmniVoice"}]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# Usage elsewhere:
{:ok, audio} = OmnivoiceEx.generate(OmniVoiceServer, "Hello!", seed: 1)
```

### Timeouts and Backpressure

- `generate/3` and `await_ready/2` accept a `timeout` argument.
- In production:
  - Never use unlimited timeouts in HTTP handlers or worker loops.
  - Use per-request timeouts (e.g., 30–120s depending on length) so long-running or stuck generations do not freeze processes.

Example:

```elixir
case OmnivoiceEx.generate(OmniVoiceServer, text, opts, timeout: 60_000) do
  {:ok, audio} ->
    # handle audio
  {:error, :timeout} ->
    # fallback / retry / user message
  {:error, reason} ->
    # log and handle
end
```

If your system is under heavy load:

- Consider a worker pool (e.g., Quantum, Oban) to isolate TTS jobs.
- Use backoff + limited retries instead of aggressive parallel attempts on the same server.

### Error Handling

OmnivoiceEx can return errors from:

- Model failures / OOM
- Invalid inputs
- Bridge crashes

General pattern:

```elixir
case OmnivoiceEx.generate(OmniVoiceServer, text, opts) do
  {:ok, audio} ->
    # success

  {:error, :timeout} ->
    Logger.warn("TTS request timed out")

  {:error, msg} when is_binary(msg) ->
    Logger.error("TTS bridge error: #{msg}")

  {:error, other} ->
    Logger.error("TTS unexpected error: #{inspect(other)}")
end
```

If the Python bridge process exits unexpectedly:

- The GenServer will transition to an error status.
- In production, wrap OmnivoiceEx in a Supervisor with `restart: :transient` or `:permanent` depending on your policy.

### Telemetry and Monitoring

OmnivoiceEx emits telemetry events you can use for observability:

- `[:omnivoice_ex, :generate]`:
  - Measured: `%{duration_ms: float()}` — time to generate audio.
- `[:omnivoice_ex, :await_ready]`:
  - Measured: model load duration.

Example: attach a handler in your application:

```elixir
defmodule MyApp do
  def start(_type, _args) do
    children = [
      MyApp.OmniVoiceSupervisor,
      {TelemetryPoller, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)

    :telemetry.attach_many(
      "omnivoice-ex-logger",
      [
        [:omnivoice_ex, :generate],
        [:omnivoice_ex, :await_ready]
      ],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event(event, measurements, _meta, _config) do
    Logger.debug(
      "OmnivoiceEx #{inspect(event)} duration_ms=#{measurements.duration_ms}"
    )
  end
end
```

You can plug this into Prometheus, Grafana, or your internal metrics stack.

### Deployment Notes

- Python environment:
  - Run `mix omnivoice_ex.setup` in your build / deploy step to install required pip packages.
  - Ensure the same Python interpreter is available at runtime as during setup.
- GPU:
  - Use a dedicated container or VM with stable GPU drivers and sufficient memory.
  - Avoid overcommitting GPUs; OmniVoice + large context can use several GBs of VRAM.
- Determinism in production:
  - For content pipelines where you must be able to reproduce outputs (e.g., logs, audits), always pass a `seed` and keep temperatures at 0.

### Common Pitfalls (FAQ-style)

- “Why is startup slow?”
  - The model loads into memory on first start. This is expected; use `await_ready/2` with a generous timeout and cache the server instead of restarting it frequently.
- “Why are concurrent requests blocking each other?”
  - The Python bridge processes one request at a time. For high concurrency, deploy multiple instances (e.g., one per GPU) and load-balance between them.
- “Audio sounds different across runs.”
  - If you need stable output, set `seed`, `position_temperature: 0.0`, `class_temperature: 0.0`. Without these, outputs may vary due to stochastic sampling.
- “Language detection seems random for mixed-language text.”
  - Set `language` explicitly (e.g., `"zh"` or `"en"`) when mixing languages in the same prompt.

## License

Apache 2.0 — see [LICENSE](LICENSE).

## Related

- [OmniVoice on HuggingFace](https://huggingface.co/k2-fsa/OmniVoice)
- [VoxCPMEx](https://hex.pm/packages/voxcpmex) — Elixir wrapper for VoxCPM2
