defmodule OmnivoiceEx.Server do
  @moduledoc """
  GenServer that manages a Python OmniVoice bridge via Erlang Port.

  ## Protocol

  Frame format: `[4-byte BE total_length][msgpack-encoded payload]`

  Audio is WAV bytes inside msgpack — no base64.

  ## Operations

    * `init` — Load model from HuggingFace
    * `generate` — TTS synthesis (synchronous, returns full audio)
    * `ping` — Health check
  """

  use GenServer

  require Logger

  @type model_option ::
          {:model, String.t()}
          | {:device, String.t()}
          | {:dtype, String.t()}
          | {:name, atom()}

  @type start_opts :: [model_option()]

  @type generate_opt ::
          {:ref_audio, String.t()}
          | {:ref_text, String.t()}
          | {:instruct, String.t()}
          | {:language, String.t()}
          | {:duration, float()}
          | {:speed, float()}
          | {:num_step, pos_integer()}
          | {:guidance_scale, float()}

  @default_model "k2-fsa/OmniVoice"
  @default_device "cuda"
  @default_dtype "float16"
  @frame_header_bytes 4

  # =========================================================================
  # Client API
  # =========================================================================

  @spec start_link(start_opts()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns runtime model info: device, sample_rate, status."
  @spec info(GenServer.server()) :: map()
  def info(server) do
    GenServer.call(server, :info)
  end

  @doc """
  Waits for the model to finish loading.

  Returns `:ok` when ready, `{:error, :loading}` if still initializing,
  or `{:error, reason}` if initialization failed.
  """
  @spec await_ready(GenServer.server(), timeout()) :: :ok | {:error, term()}
  def await_ready(server, timeout \\ 120_000) do
    GenServer.call(server, :await_ready, timeout)
  end

  @doc "Gracefully stops the GenServer and the Python bridge process."
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server, :normal)
  end

  @spec generate(GenServer.server(), String.t(), [generate_opt()]) ::
          {:ok, binary()} | {:error, term()}
  def generate(server, text, opts \\ []) do
    generate(server, text, opts, 120_000)
  end

  @spec generate(GenServer.server(), String.t(), [generate_opt()], timeout()) ::
          {:ok, binary()} | {:error, term()}
  def generate(server, text, opts, timeout) do
    GenServer.call(server, {:generate, text, opts}, timeout)
  end

  @spec save(binary(), Path.t()) :: :ok | {:error, term()}
  def save(audio, path) when is_binary(audio) do
    File.write(path, audio)
  end

  # =========================================================================
  # GenServer Callbacks
  # =========================================================================

  @impl true
  def init(opts) do
    model = Keyword.get(opts, :model, @default_model)
    device = Keyword.get(opts, :device, @default_device)
    dtype = Keyword.get(opts, :dtype, @default_dtype)

    bridge_path = Path.join(:code.priv_dir(:omnivoice_ex), "python/omnivoice_ex_bridge.py")

    unless File.exists?(bridge_path) do
      {:stop, "Python bridge not found: #{bridge_path}"}
    else
      python_cmd =
        System.find_executable("python3") || System.find_executable("python") || "python3"

      port =
        Port.open({:spawn_executable, python_cmd}, [
          :binary,
          :use_stdio,
          :exit_status,
          :stderr_to_stdout,
          args: ["-u", bridge_path]
        ])

      send_frame(port, %{
        "type" => "init",
        "model" => model,
        "device" => device,
        "dtype" => dtype
      })

      state = %{
        port: port,
        model: model,
        status: :loading,
        device: nil,
        sample_rate: nil,
        buffer: <<>>,
        pending: :queue.new()
      }

      {:ok, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state.port do
      Port.close(state.port)
    end

    :ok
  end

  # -- call handlers ----------------------------------------------------------

  @impl true
  def handle_call(:info, _from, state) do
    {:reply,
     %{
       status: state.status,
       device: state.device,
       sample_rate: state.sample_rate,
       model: state.model
     }, state}
  end

  def handle_call(:await_ready, _from, state) do
    case state.status do
      :ready -> {:reply, :ok, state}
      :loading -> {:reply, {:error, :loading}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:generate, text, opts}, from, state) do
    if state.status != :ready do
      {:reply, {:error, :not_ready}, state}
    else
      t0 = System.monotonic_time()

      msg =
        Map.merge(%{"type" => "generate", "text" => text}, stringify_generate_keys(opts))

      send_frame(state.port, msg)

      {:noreply, %{state | pending: :queue.in({from, :generate, t0}, state.pending)}}
    end
  end

  # -- port messages ----------------------------------------------------------

  @impl true
  def handle_info({_port, {:data, data}}, state) do
    {msgs, new_buffer} = parse_frames(state.buffer <> data)

    state =
      Enum.reduce(msgs, %{state | buffer: new_buffer}, fn msg, acc ->
        handle_message(msg, acc)
      end)

    {:noreply, state}
  end

  @impl true
  def handle_info({_port, {:exit_status, status}}, state) do
    Logger.error("OmniVoice bridge exited with status #{status}")
    {:stop, {:bridge_exit, status}, state}
  end

  # =========================================================================
  # Message dispatch
  # =========================================================================

  defp handle_message(%{"status" => "ok"} = msg, state) do
    cond do
      # Init response: {"status": "ok", "device": "...", "sample_rate": ...}
      Map.has_key?(msg, "device") ->
        Logger.info("OmniVoice loaded on #{msg["device"]}, sr=#{msg["sample_rate"]}")

        %{state | status: :ready, device: msg["device"], sample_rate: msg["sample_rate"]}

      # Generate response: {"status": "ok", "audio": <WAV bytes>, ...}
      Map.has_key?(msg, "audio") ->
        {{:value, {from, _type, t0}}, new_pending} = :queue.out(state.pending)

        emit_telemetry(:generate, t0)

        GenServer.reply(from, {:ok, msg["audio"]})
        %{state | pending: new_pending}

      true ->
        {:noreply, state}
    end
  end

  defp handle_message(%{"status" => "error", "error" => error}, state) do
    Logger.error("Bridge error: #{error}")

    {new_pending, updated_state} =
      case :queue.out(state.pending) do
        {{:value, {from, _type, _t0}}, new_q} ->
          GenServer.reply(from, {:error, error})
          {new_q, state}

        {:empty, _} ->
          {state.pending, state}
      end

    # If this error arrived during init, update status
    updated_state =
      if updated_state.status == :loading do
        %{updated_state | status: {:error, error}}
      else
        updated_state
      end

    %{updated_state | pending: new_pending}
  end

  defp handle_message(%{"message" => "pong"}, state) do
    # Ping response — nothing to do
    state
  end

  # =========================================================================
  # Helpers
  # =========================================================================

  defp send_frame(port, msg) do
    data = msg |> Msgpax.pack!() |> IO.iodata_to_binary()
    len = byte_size(data) + @frame_header_bytes
    frame = <<len::32-unsigned-big-integer>> <> data
    send(port, {self(), {:command, frame}})
  end

  defp parse_frames(binary) do
    parse_frames_loop(binary, [])
  end

  defp parse_frames_loop(rest, acc) when byte_size(rest) < @frame_header_bytes do
    {Enum.reverse(acc), rest}
  end

  defp parse_frames_loop(<<len::32-unsigned-big-integer, rest::binary>>, acc) do
    payload_len = len - @frame_header_bytes

    case rest do
      <<payload::binary-size(payload_len), rest::binary>> ->
        msg = Msgpax.unpack!(payload)
        parse_frames_loop(rest, [msg | acc])

      _ ->
        # Incomplete frame — put the header back
        {Enum.reverse(acc), <<len::32-unsigned-big-integer>> <> rest}
    end
  end

  defp emit_telemetry(event, t0) do
    elapsed_us = System.monotonic_time() - t0
    elapsed_ms = System.convert_time_unit(elapsed_us, :native, :millisecond)

    :telemetry.execute(
      [:omnivoice_ex, event],
      %{duration_ms: elapsed_ms},
      %{}
    )
  end

  defp stringify_generate_keys(opts) do
    opts
    |> Enum.map(fn
      {:ref_audio, v} -> {"ref_audio", v}
      {:ref_text, v} -> {"ref_text", v}
      {:instruct, v} -> {"instruct", v}
      {:language, v} -> {"language", v}
      {:duration, v} -> {"duration", v}
      {:speed, v} -> {"speed", v}
      {:num_step, v} -> {"num_step", v}
      {:guidance_scale, v} -> {"guidance_scale", v}
    end)
    |> Map.new()
  end
end
