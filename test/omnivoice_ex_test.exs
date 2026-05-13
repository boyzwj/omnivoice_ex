defmodule OmnivoiceExTest do
  use ExUnit.Case
  doctest OmnivoiceEx

  describe "save/2" do
    test "writes audio bytes to file" do
      path = "/tmp/omnivoice_ex_test_delete_me.wav"
      audio = <<82, 73, 70, 70, 0, 0, 0, 0, 87, 65, 86, 69>>  # Minimal WAV header
      assert :ok = OmnivoiceEx.save(audio, path)
      assert File.exists?(path)
      File.rm!(path)
    end

    test "returns error for invalid path" do
      assert {:error, _} = OmnivoiceEx.save(<<0>>, "/nonexistent/dir/file.wav")
    end
  end

  describe "info/1" do
    test "returns map with expected keys" do
      {:ok, pid} = OmnivoiceEx.Server.start_link([])
      info = OmnivoiceEx.info(pid)

      assert is_map(info)
      assert Map.has_key?(info, :status)
      assert Map.has_key?(info, :device)
      assert Map.has_key?(info, :sample_rate)
      assert Map.has_key?(info, :model)

      GenServer.stop(pid)
    end
  end

  describe "start_link/1" do
    test "starts GenServer with default model" do
      {:ok, pid} = OmnivoiceEx.Server.start_link([])
      assert is_pid(pid)
      GenServer.stop(pid)
    end

    test "accepts custom model option" do
      {:ok, pid} = OmnivoiceEx.Server.start_link(model: "k2-fsa/OmniVoice", device: "cpu")
      assert is_pid(pid)
      GenServer.stop(pid)
    end
  end

  describe "await_ready/1" do
    test "returns loading error during init" do
      {:ok, pid} = OmnivoiceEx.Server.start_link([])
      assert {:error, :loading} = OmnivoiceEx.await_ready(pid)
      GenServer.stop(pid)
    end
  end
end
