defmodule OmnivoiceEx do
  @moduledoc """
  Elixir wrapper for [OmniVoice](https://huggingface.co/k2-fsa/OmniVoice) —
  a unified speech generation model from K2-FSA.

  **Voice Cloning** · **Voice Design (instruction-based)** · **Multilingual** · **24kHz output**.

  ## Features

    * 🎤 **Voice Cloning** — Clone any voice from a reference audio clip
    * 🎨 **Voice Design** — Describe a voice in natural language and generate it
    * 🌍 **Multilingual** — Supports multiple languages with automatic detection
    * ⚡ **Fast Inference** — Optimized for GPU (CUDA/MPS) and CPU
    * 🔊 **24kHz WAV Output** — Studio-quality audio

  ## Protocol

  OmnivoiceEx uses **MessagePack** over **binary-framed** Erlang Ports.
  Audio is transmitted as WAV bytes inside msgpack — no base64 overhead.

  ## Quick Start

      {:ok, pid} = OmnivoiceEx.start_link(device: "cuda")
      :ok = OmnivoiceEx.await_ready(pid)
      {:ok, audio} = OmnivoiceEx.generate(pid, "Hello, world!")
      :ok = OmnivoiceEx.save(audio, "output.wav")

  ## Voice Design (instruction-based)

      {:ok, audio} = OmnivoiceEx.generate(pid, "Welcome to our service!",
        instruct: "A warm, professional female broadcaster"
      )

  ## Voice Cloning

      {:ok, audio} = OmnivoiceEx.generate(pid, "This is my voice clone!",
        ref_audio: "/path/to/reference.wav",
        ref_text: "The transcript of the reference audio"
      )

  ## Requirements

    * Python ≥ 3.10, `omnivoice` + `msgpack` + `numpy` + `soundfile` pip packages
    * CUDA GPU, Apple Silicon (MPS), or CPU
    * Elixir ≥ 1.14

  ## Installation

      # mix.exs
      {:omnivoice_ex, "~> 0.1.0"}

      # Install Python deps
      mix omnivoice_ex.setup
  """

  alias OmnivoiceEx.Server

  @type audio :: binary()

  @type generate_opt ::
          {:ref_audio, String.t()}
          | {:ref_text, String.t()}
          | {:instruct, String.t()}
          | {:language, String.t()}
          | {:duration, float()}
          | {:speed, float()}
          | {:num_step, pos_integer()}
          | {:guidance_scale, float()}
          | {:seed, non_neg_integer()}
          | {:position_temperature, float()}
          | {:class_temperature, float()}

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @doc "Returns runtime model information."
  @spec info(GenServer.server()) :: map()
  defdelegate info(server), to: Server

  @doc "Gracefully stops the server and Python bridge."
  @spec stop(GenServer.server()) :: :ok
  defdelegate stop(server), to: Server

  @doc """
  Starts an OmniVoice model server.

  ## Options

    * `:model` — HuggingFace model ID. Default: `"k2-fsa/OmniVoice"`
    * `:device` — `"cuda"`, `"cpu"`, `"mps"`. Default: `"cuda"`
    * `:dtype` — `"float16"`, `"float32"`, `"bfloat16"`. Default: `"float16"`
    * `:name` — Optional GenServer name
  """
  @spec start_link(Server.start_opts()) :: GenServer.on_start()
  defdelegate start_link(opts), to: Server

  @doc """
  Waits for the model to finish loading. Returns `:ok` when ready.
  """
  @spec await_ready(GenServer.server(), timeout()) :: :ok | {:error, term()}
  defdelegate await_ready(server, timeout \\ 120_000), to: Server

  # ---------------------------------------------------------------------------
  # Generation
  # ---------------------------------------------------------------------------

  @doc """
  Generates speech audio from text. Returns `{:ok, audio_wav}`.

  ## Options

    * `:ref_audio` — Path to reference audio for voice cloning
    * `:ref_text` — Transcript of reference audio (improves clone quality)
    * `:instruct` — Voice instruction for design (e.g. "A warm female broadcaster")
    * `:language` — OmniVoice language ID (e.g. `"zh"`, `"en"`, `"ja"`, `"ko"`, `"yue"`). Auto-detected from text if omitted. For mixed-language content, set this explicitly to avoid unstable detection.

  Common IDs: `zh` (Chinese), `en` (English), `ja` (Japanese), `ko` (Korean), `yue` (Cantonese), `fr` (French), `de` (German), `es` (Spanish), `ru` (Russian), `pt` (Portuguese), `it` (Italian), `th` (Thai), `vi` (Vietnamese), `hi` (Hindi), `ar` (Arabic), `nl` (Dutch), `pl` (Polish), `sv` (Swedish), `tr` (Turkish).

  Full list of 646 languages: [OmniVoice docs/languages.md](https://github.com/k2-fsa/OmniVoice/blob/master/docs/languages.md)
    * `:duration` — Target duration in seconds
    * `:speed` — Playback speed factor
    * `:num_step` — Diffusion steps (higher = better quality, slower). Default: `32`
    * `:guidance_scale` — Classifier-free guidance. Default: `2.0`
    * `:seed` — Random seed for reproducible generation. Default: `42`.
    * `:position_temperature` — Mask-position selection temperature. `0` = greedy (deterministic). Default: `0.0`.
    * `:class_temperature` — Token sampling temperature. `0` = greedy (deterministic). Default: `0.0`.

  ## Examples

      # Basic
      {:ok, audio} = OmnivoiceEx.generate(pid, "Hello!")
      :ok = OmnivoiceEx.save(audio, "out.wav")

      # Voice Design
      {:ok, audio} = OmnivoiceEx.generate(pid,
        "Welcome to the show!",
        instruct: "A deep, authoritative male narrator"
      )

      # Voice Cloning
      {:ok, audio} = OmnivoiceEx.generate(pid, "Hello in my voice!",
        ref_audio: "/path/to/ref.wav",
        ref_text: "This is my reference transcript"
      )

      # Quality tuning
      {:ok, audio} = OmnivoiceEx.generate(pid, "High quality speech.",
        num_step: 64, guidance_scale: 3.0
      )
  """
  @spec generate(GenServer.server(), String.t(), [generate_opt()]) ::
          {:ok, audio()} | {:error, term()}
  defdelegate generate(server, text, opts \\ []), to: Server

  @spec generate(GenServer.server(), String.t(), [generate_opt()], timeout()) ::
          {:ok, audio()} | {:error, term()}
  defdelegate generate(server, text, opts, timeout), to: Server

  # ---------------------------------------------------------------------------
  # I/O
  # ---------------------------------------------------------------------------

  @doc """
  Saves audio binary to a WAV file.
  """
  @spec save(audio(), Path.t()) :: :ok | {:error, term()}
  defdelegate save(audio, path), to: Server
end
