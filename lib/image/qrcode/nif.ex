defmodule Image.QRCode.Nif do
  @moduledoc false

  @on_load :load_nif

  @doc false
  def load_nif do
    nif_path = :filename.join(:code.priv_dir(:image_qrcode), ~c"image_qrcode_nif")
    :erlang.load_nif(nif_path, 0)
  end

  @doc false
  def encode(_text, _ecc, _version_min, _version_max, _mask, _boost_ecc) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def decode(_grayscale, _width, _height) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
