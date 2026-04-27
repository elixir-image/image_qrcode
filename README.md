# Image.QRCode

QR code encoding and decoding for the [Image](https://hex.pm/packages/image)
library, implemented as a NIF over two small, well-regarded C libraries:

* **Encoding** — [nayuki/QR-Code-generator](https://github.com/nayuki/QR-Code-generator) (MIT).
* **Decoding** — [dlbeer/quirc](https://github.com/dlbeer/quirc) (ISC).

Both libraries are vendored under `c_src/` and statically linked into the
NIF, so the package has no system-library dependencies beyond a C compiler
on platforms where a precompiled artefact is not available.

The standard image type for both input and output is `t:Vix.Vips.Image.t/0`.
Conversion to and from the raw module / grayscale buffers required by the
underlying C libraries is performed implicitly.

## Installation

Add `:image_qrcode` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:image_qrcode, "~> 0.1"}
  ]
end
```

The NIF is shipped as a precompiled artefact for the common Linux, macOS and
Windows targets — no C toolchain is required on those platforms. On any other
target, `mix deps.compile` will fall back to building from the vendored
sources, which needs only a C11 compiler and `make`.

## Usage

### Encoding

`Image.QRCode.encode/2` takes a string and returns a single-band 8-bit
`t:Vix.Vips.Image.t/0` rendering of the QR code:

```elixir
{:ok, image} = Image.QRCode.encode("https://example.com")
:ok = Vix.Vips.Image.write_to_file(image, "qr.png")
```

Common options:

* `:ecc` — `:low | :medium | :quartile | :high` (default `:medium`).
* `:scale` — pixels per QR module (default `4`).
* `:quiet` — quiet-zone width in modules (default `4`, the QR spec minimum).
* `:version_min` / `:version_max` — bounds for the QR version (1..40).
* `:mask` — `:auto` (default) or an integer `0..7`.
* `:boost_ecc` — let the encoder upgrade ECC if the chosen version has
  spare capacity (default `true`).

### Decoding

`Image.QRCode.decode/1` takes any `t:Vix.Vips.Image.t/0` and returns a list of
decoded QR codes. The image is implicitly converted to grayscale, so RGB,
RGBA, float-format and multi-band inputs are all accepted:

```elixir
{:ok, image} = Vix.Vips.Image.new_from_file("qr.png")
{:ok, [%{payload: payload, version: version, corners: corners}]} =
  Image.QRCode.decode(image)
```

Each decoded entry is a map with `:payload`, `:version`, `:ecc_level`,
`:mask`, `:data_type`, `:eci` and `:corners` (the four corners of the code
in image coordinates, top-left clockwise).

## Concurrency

Both encoder and decoder hold no shared mutable state — each call allocates
its own scratch buffers — and the NIF is scheduled on dirty CPU schedulers,
so concurrent invocation from many processes is safe and parallelised.
A stress harness (`test/concurrency_test.exs`, tagged `:concurrency`)
verifies this property by running 500 round-trips at high concurrency.

## License

This library is released under the Apache-2.0 license. The vendored
encoder is MIT-licensed (Nayuki) and the vendored decoder is ISC-licensed
(Daniel Beer); their license headers are retained in the source tree under
`c_src/nayuki` and `c_src/quirc`.
