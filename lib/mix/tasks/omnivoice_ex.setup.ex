defmodule Mix.Tasks.OmnivoiceEx.Setup do
  use Mix.Task

  @shortdoc "Install Python dependencies for OmniVoice"
  @moduledoc """
  Installs Python dependencies required by OmniVoiceEx bridge.

      mix omnivoice_ex.setup

  This installs:
    * omnivoice — K2-FSA's OmniVoice Python library
    * msgpack — Protocol serialization
    * numpy, soundfile — Audio utilities
    * torch — PyTorch (omitted if already installed)
  """

  @impl true
  def run(_args) do
    python = System.find_executable("python3") || System.find_executable("python") || "python3"

    deps = [
      "omnivoice",
      "msgpack",
      "numpy",
      "soundfile"
    ]

    IO.puts("Installing Python dependencies via pip...")
    IO.puts("  #{Enum.join(deps, "\n  ")}")

    {output, exit_code} =
      System.cmd(python, ["-m", "pip", "install", "--quiet" | deps],
        stderr_to_stdout: true,
        into: IO.stream(:stdio, :line)
      )

    if exit_code == 0 do
      IO.puts("\n✓ Python dependencies installed successfully.")
    else
      IO.puts("\n⚠ pip install exited with status #{exit_code}")
      IO.puts(output)
    end
  end
end
