defmodule Image.QRCodeTest do
  use ExUnit.Case, async: true
  doctest Image.QRCode

  alias Vix.Vips.Image, as: Vimage
  alias Vix.Vips.Operation

  describe "encode/2" do
    test "produces a single-band 8-bit Vimage" do
      assert {:ok, image} = Image.QRCode.encode("HELLO WORLD")
      assert Vimage.bands(image) == 1
      assert Vimage.format(image) == :VIPS_FORMAT_UCHAR
      assert Vimage.width(image) == Vimage.height(image)
    end

    test "respects scale and quiet options" do
      assert {:ok, image} = Image.QRCode.encode("HI", scale: 8, quiet: 2)
      # Smallest QR is 21 modules. With quiet=2 and scale=8 that's (21+4)*8 = 200.
      assert Vimage.width(image) == 200
    end

    test "honours version_max overflow" do
      huge = String.duplicate("x", 5_000)
      assert {:error, :encode_failed} = Image.QRCode.encode(huge, version_max: 5)
    end

    test "rejects invalid ecc level" do
      assert {:error, {:invalid_ecc, :bogus}} = Image.QRCode.encode("hi", ecc: :bogus)
    end

    test "rejects invalid scale" do
      assert {:error, {:invalid_render, 0, 4}} = Image.QRCode.encode("hi", scale: 0)
    end
  end

  describe "decode/1" do
    test "round-trips a payload through a Vimage" do
      payload = "https://example.com/HELLO"
      assert {:ok, image} = Image.QRCode.encode(payload)
      assert {:ok, [decoded]} = Image.QRCode.decode(image)
      assert decoded.payload == payload
      assert decoded.version >= 1
    end

    test "decodes from an RGB image (implicit colourspace conversion)" do
      assert {:ok, gray} = Image.QRCode.encode("RGB-INPUT")
      assert {:ok, rgb} = Operation.colourspace(gray, :VIPS_INTERPRETATION_sRGB)
      assert Vimage.bands(rgb) == 3
      assert {:ok, [%{payload: "RGB-INPUT"}]} = Image.QRCode.decode(rgb)
    end

    test "returns empty list on a blank image" do
      assert {:ok, blank} =
               Vimage.new_from_binary(
                 :binary.copy(<<255>>, 100 * 100),
                 100,
                 100,
                 1,
                 :VIPS_FORMAT_UCHAR
               )

      assert {:ok, []} = Image.QRCode.decode(blank)
    end
  end
end
