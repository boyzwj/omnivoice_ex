# AGENTS.md

## Project

Elixir library wrapping OmniVoice (K2-FSA speech model) via Erlang Port + Python bridge.

- **Language:** Elixir (>= 1.14), **not** Node/Python/Rust
- **Build:** `mix compile`, `mix test`, `mix format` (line_length: 100)
- **Setup:** `mix setup` (alias for `mix omnivoice_ex.setup`) — installs Python deps via pip
- **Python runtime req:** `python3` with `pip install omnivoice msgpack numpy soundfile`
- **App:** Library published on Hex, not a standalone app. The OTP supervisor starts with 0 children; servers are started on-demand by the user.

## Architecture

```
OmnivoiceEx (public API) → OmnivoiceEx.Server (GenServer) → Erlang Port → Python process
```

- **Protocol:** Binary-framed MessagePack (`[4-byte BE length][msgpack map]`) over stdin/stdout
- **Bridge script:** `priv/python/omnivoice_ex_bridge.py`
- **One Python process** per GenServer instance — model lives in Python process memory
- **Device fallback:** CUDA→CPU, MPS→CPU graceful degradation
- **Defaults:** model `k2-fsa/OmniVoice`, device `cuda`, dtype `float16`, timeout 120s

## Testing

- `mix test` — all tests in `test/` (no test runner config beyond default ExUnit)
- Tests do NOT require a GPU or Python bridge — they test the Elixir API contract without actual model inference
- `await_ready` on a fresh server returns `{:error, :loading}` (model isn't loaded in tests)

## Conventions

- **Elixir formatter** with 100-char line length (`.formatter.exs`)
- **No CI pipelines** configured
- **No Dockerfiles** — Python deps run natively
- **Generated/ignored artifacts:** `_build/`, `deps/`, `.venv/`, `*.wav`, `*.mp3`

## Port pitfalls

- **Never use `:stderr_to_stdout`** — stderr text (Python warnings, log lines) corrupts the binary MessagePack frame stream. Stderr from the Python process goes to the BEAM error logger by default; keep it separate.
- Python bridge writes loading progress to `sys.stderr` (lines 120–131 in bridge script). These must never interleave with stdout binary frames.

## Notable quirks

- `generate/3` blocks via `GenServer.call` (120s default timeout). The Python bridge processes requests asynchronously via port messages.
- Must call `await_ready/1` before `generate/3` — returns `{:error, :not_ready}` otherwise.
- Telemetry events emitted under `[:omnivoice_ex, :generate]` with `%{duration_ms: ...}`.
- `save/2` writes raw WAV bytes — the audio is already encoded by the Python bridge.
