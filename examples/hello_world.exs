# Hello World — Basic TTS
#
# Usage: elixir examples/hello_world.exs

{:ok, pid} = OmnivoiceEx.start_link()
IO.puts("Loading OmniVoice model...")
:ok = OmnivoiceEx.await_ready(pid, 300_000)
IO.puts("Model ready!")

{:ok, audio} = OmnivoiceEx.generate(pid, "Hello, world! This is OmniVoice speaking.")
:ok = OmnivoiceEx.save(audio, "output_hello.wav")
IO.puts("Saved to output_hello.wav")

OmnivoiceEx.stop(pid)
