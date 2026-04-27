defmodule Image.QRCode.ConcurrencyTest do
  @moduledoc """
  Stress test for NIF thread-safety.

  Both `nayuki/qrcodegen` and `dlbeer/quirc` are stateless across calls — each
  invocation owns its scratch buffers and decoder context — and our NIF holds
  no global mutable state beyond load-time atom terms. This harness exercises
  that property by running many concurrent encode/decode round-trips on the
  dirty CPU schedulers and asserting every payload survives the round trip.

  Tagged `:concurrency` so it can be run on demand:

      mix test --only concurrency
  """

  use ExUnit.Case, async: true

  @moduletag :concurrency
  @moduletag timeout: 120_000

  @iterations 500
  # Push past the dirty-CPU scheduler count to force contention.
  @max_concurrency System.schedulers_online() * 4

  describe "concurrent round-trips" do
    test "encode+decode survives heavy concurrency without crashing or corrupting payloads" do
      payloads = generate_payloads(@iterations)

      results =
        payloads
        |> Task.async_stream(
          &round_trip/1,
          max_concurrency: @max_concurrency,
          timeout: 60_000,
          ordered: false
        )
        |> Enum.to_list()

      assert length(results) == @iterations

      for {:ok, outcome} <- results do
        assert {:roundtrip_ok, input, output} = outcome,
               "expected successful round-trip, got: #{inspect(outcome)}"

        assert input == output
      end
    end

    test "interleaved encode-only and decode-only workloads coexist" do
      # Pre-build a set of images so the decode workers don't depend on encode workers.
      images =
        for i <- 1..50 do
          payload = "decode-target-#{i}"
          {:ok, image} = Image.QRCode.encode(payload, scale: 4)
          {payload, image}
        end

      # Two streams of work running in parallel: pure encoders and pure decoders.
      encode_task =
        Task.async(fn ->
          1..@iterations
          |> Task.async_stream(
            fn i -> {:ok, _} = Image.QRCode.encode("encode-only-#{i}", scale: 3) end,
            max_concurrency: @max_concurrency,
            ordered: false,
            timeout: 60_000
          )
          |> Stream.run()
        end)

      decode_task =
        Task.async(fn ->
          for _ <- 1..@iterations do
            {payload, image} = Enum.random(images)
            {:ok, [%{payload: ^payload}]} = Image.QRCode.decode(image)
          end
        end)

      Task.await_many([encode_task, decode_task], 90_000)
    end
  end

  defp generate_payloads(count) do
    for i <- 1..count do
      # Mix of short, long, and varied content so the encoder picks different
      # versions / masks across the run.
      tag = Base.encode16(:crypto.strong_rand_bytes(6))

      case rem(i, 3) do
        0 -> "https://example.com/#{i}/#{tag}"
        1 -> "ITEM-#{i}-#{tag}"
        2 -> :binary.copy("y", 32) <> "-#{i}-#{tag}"
      end
    end
  end

  defp round_trip(payload) do
    with {:ok, image} <- Image.QRCode.encode(payload, scale: 4),
         {:ok, [%{payload: decoded}]} <- Image.QRCode.decode(image) do
      {:roundtrip_ok, payload, decoded}
    else
      other -> {:roundtrip_failed, payload, other}
    end
  end
end
