# Voice Design — generate a voice from text description
#
# Usage: elixir examples/voice_design.exs

{:ok, pid} = OmnivoiceEx.start_link()
IO.puts("Loading OmniVoice model...")
:ok = OmnivoiceEx.await_ready(pid, 300_000)

text = "Welcome to our luxury hotel. We hope you enjoy your stay with us."
instruct = "A warm, professional female concierge with a gentle British accent"

IO.puts("Generating: #{instruct}")
IO.puts("Text: #{text}")

{:ok, audio} = OmnivoiceEx.generate(pid, text, instruct: instruct)
:ok = OmnivoiceEx.save(audio, "output_voice_design.wav")
IO.puts("Saved to output_voice_design.wav")

OmnivoiceEx.stop(pid)
