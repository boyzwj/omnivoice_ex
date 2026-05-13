# Voice Cloning — clone a voice from reference audio
#
# Usage: elixir examples/voice_cloning.exs
#
# Requires a reference WAV file at /tmp/ref.wav (or change path below)

{:ok, pid} = OmnivoiceEx.start_link()
IO.puts("Loading OmniVoice model...")
:ok = OmnivoiceEx.await_ready(pid, 300_000)

ref_path = "/tmp/ref.wav"

unless File.exists?(ref_path) do
  IO.puts("⚠ Reference audio not found at #{ref_path}")
  IO.puts("  Place a WAV file there and re-run this example.")
  System.halt(1)
end

text = "This is a cloned voice speaking naturally in English."
ref_text = "Optional: the transcript of the reference audio"

IO.puts("Cloning voice from #{ref_path}...")

{:ok, audio} = OmnivoiceEx.generate(pid, text,
  ref_audio: ref_path,
  ref_text: ref_text
)

:ok = OmnivoiceEx.save(audio, "output_cloned.wav")
IO.puts("Saved to output_cloned.wav")

OmnivoiceEx.stop(pid)
