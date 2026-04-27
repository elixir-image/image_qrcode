defmodule Image.QRCode do
  @moduledoc """
  Encode and decode QR codes via NIF bindings.

  Encoding is provided by [nayuki/QR-Code-generator](https://github.com/nayuki/QR-Code-generator)
  (MIT). Decoding is provided by [dlbeer/quirc](https://github.com/dlbeer/quirc) (ISC).
  Both libraries are vendored under `c_src/` and statically linked into the NIF.

  The standard image type for both input and output is `t:Vix.Vips.Image.t/0`.
  Conversion to and from the raw module/grayscale buffers required by the
  underlying C libraries is performed implicitly.
  """

  alias Image.QRCode.Nif
  alias Vix.Vips.Image, as: Vimage
  alias Vix.Vips.Operation

  @ecc_levels %{low: 0, medium: 1, quartile: 2, high: 3}
  @valid_ecc Map.keys(@ecc_levels)

  @typedoc "Error correction level."
  @type ecc :: :low | :medium | :quartile | :high

  @typedoc "A successfully decoded QR code."
  @type decoded :: %{
          payload: binary(),
          version: 1..40,
          ecc_level: 0..3,
          mask: 0..7,
          data_type: integer(),
          eci: non_neg_integer(),
          corners:
            {{integer(), integer()}, {integer(), integer()}, {integer(), integer()},
             {integer(), integer()}}
        }

  @doc """
  Encodes `text` as a QR code image.

  ### Arguments

  * `text` is a `t:String.t/0` to encode. UTF-8 is encoded as a byte-mode segment.

  ### Options

  * `:ecc` is the error correction level. One of `:low`, `:medium`, `:quartile`,
    `:high`. The default is `:medium`.

  * `:version_min` is the minimum QR version (size). An integer in `1..40`.
    The default is `1`.

  * `:version_max` is the maximum QR version (size). An integer in `1..40`.
    The default is `40`.

  * `:mask` is the data mask pattern. `:auto` selects the optimal mask (the
    default), or an integer in `0..7` to force a specific mask.

  * `:boost_ecc` is a boolean. When `true`, the encoder may upgrade the ECC
    level beyond `:ecc` if the chosen version has spare capacity. The default
    is `true`.

  * `:scale` is the pixel size of each QR module in the rendered image. A
    positive integer. The default is `4`.

  * `:quiet` is the quiet-zone width in modules surrounding the code. A
    non-negative integer. The default is `4` (the QR specification minimum).

  ### Returns

  * `{:ok, image}` where `image` is a single-band 8-bit `t:Vix.Vips.Image.t/0`
    with `0` for dark modules and `255` for light modules.

  * `{:error, reason}` on encoding failure (typically `:encode_failed` when
    the input does not fit `version_max` at the requested ECC).

  ### Examples

      iex> {:ok, image} = Image.QRCode.encode("HELLO")
      iex> Vix.Vips.Image.bands(image)
      1

      iex> Image.QRCode.encode(String.duplicate("x", 10_000), version_max: 5)
      {:error, :encode_failed}

  """
  @spec encode(String.t(), keyword()) :: {:ok, Vimage.t()} | {:error, term()}
  def encode(text, options \\ []) when is_binary(text) and is_list(options) do
    ecc = Keyword.get(options, :ecc, :medium)
    version_min = Keyword.get(options, :version_min, 1)
    version_max = Keyword.get(options, :version_max, 40)
    mask = Keyword.get(options, :mask, :auto)
    boost_ecc = Keyword.get(options, :boost_ecc, true)
    scale = Keyword.get(options, :scale, 4)
    quiet = Keyword.get(options, :quiet, 4)

    with {:ok, ecc_int} <- ecc_to_int(ecc),
         {:ok, mask_int} <- mask_to_int(mask),
         :ok <- validate_version(version_min, version_max),
         :ok <- validate_render(scale, quiet),
         {:ok, size, modules} <-
           Nif.encode(text, ecc_int, version_min, version_max, mask_int, bool_to_int(boost_ecc)) do
      buffer = render_grayscale(modules, size, scale, quiet)
      side = (size + 2 * quiet) * scale
      Vimage.new_from_binary(buffer, side, side, 1, :VIPS_FORMAT_UCHAR)
    end
  end

  @doc """
  Decodes any QR codes present in `image`.

  The image is implicitly converted to single-band 8-bit grayscale before
  being passed to the decoder. Inputs of any colourspace, band format, or
  band count are accepted.

  ### Arguments

  * `image` is any `t:Vix.Vips.Image.t/0`.

  ### Returns

  * `{:ok, decoded}` where `decoded` is a list of `t:decoded/0` maps. The
    list is empty when no codes are detected.

  * `{:error, reason}` on internal failure.

  ### Examples

      iex> {:ok, image} = Image.QRCode.encode("HELLO")
      iex> {:ok, [%{payload: "HELLO"}]} = Image.QRCode.decode(image)

  """
  @spec decode(Vimage.t()) :: {:ok, [decoded()]} | {:error, term()}
  def decode(%Vimage{} = image) do
    with {:ok, buffer, width, height} <- to_grayscale_buffer(image) do
      Nif.decode(buffer, width, height)
    end
  end

  ## Internal

  defp to_grayscale_buffer(%Vimage{} = image) do
    with {:ok, gray} <- Operation.colourspace(image, :VIPS_INTERPRETATION_B_W),
         {:ok, gray} <- ensure_single_band(gray),
         {:ok, gray} <- Operation.cast(gray, :VIPS_FORMAT_UCHAR),
         {:ok, bytes} <- Vimage.write_to_binary(gray) do
      {:ok, bytes, Vimage.width(gray), Vimage.height(gray)}
    end
  end

  defp ensure_single_band(%Vimage{} = image) do
    case Vimage.bands(image) do
      1 -> {:ok, image}
      _ -> Operation.extract_band(image, 0, n: 1)
    end
  end

  defp render_grayscale(modules, size, scale, quiet) do
    side = (size + 2 * quiet) * scale

    for y <- 0..(side - 1), x <- 0..(side - 1), into: <<>> do
      my = div(y, scale) - quiet
      mx = div(x, scale) - quiet

      if my in 0..(size - 1) and mx in 0..(size - 1) and
           :binary.at(modules, my * size + mx) == 1 do
        <<0>>
      else
        <<255>>
      end
    end
  end

  defp ecc_to_int(level) when level in @valid_ecc, do: {:ok, Map.fetch!(@ecc_levels, level)}
  defp ecc_to_int(other), do: {:error, {:invalid_ecc, other}}

  defp mask_to_int(:auto), do: {:ok, -1}
  defp mask_to_int(m) when is_integer(m) and m in 0..7, do: {:ok, m}
  defp mask_to_int(other), do: {:error, {:invalid_mask, other}}

  defp validate_version(min, max)
       when is_integer(min) and is_integer(max) and min in 1..40 and max in 1..40 and min <= max,
       do: :ok

  defp validate_version(min, max), do: {:error, {:invalid_version, min, max}}

  defp validate_render(scale, quiet)
       when is_integer(scale) and scale > 0 and is_integer(quiet) and quiet >= 0,
       do: :ok

  defp validate_render(scale, quiet), do: {:error, {:invalid_render, scale, quiet}}

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0
end
