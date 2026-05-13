defmodule OmnivoiceEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/boyzwj/omnivoice_ex"

  def project do
    [
      app: :omnivoice_ex,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {OmnivoiceEx.Application, []}
    ]
  end

  defp deps do
    [
      {:msgpax, "~> 2.4"},
      {:telemetry, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Elixir wrapper for OmniVoice — a unified speech generation model
    from K2-FSA supporting Voice Cloning, Voice Design, and multilingual
    TTS at 24kHz. Uses MessagePack binary protocol over Erlang Ports.
    """
  end

  defp package do
    [
      name: "omnivoice_ex",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "OmniVoice" => "https://huggingface.co/k2-fsa/OmniVoice"
      },
      files: ~w(lib priv examples mix.exs README.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "OmnivoiceEx",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp aliases do
    [
      setup: ["omnivoice_ex.setup"]
    ]
  end
end
