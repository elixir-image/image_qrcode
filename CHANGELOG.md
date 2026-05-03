# Changelog

## [0.1.0] 2026-05-02

### Initial release

* `Image.QRCode.encode/2` — encodes a string to a `Vix.Vips.Image.t/0` QR code with configurable error-correction level, version range, mask, scale and quiet-zone width.

* `Image.QRCode.decode/1` — decodes any QR codes in a `Vix.Vips.Image.t/0`, with implicit conversion of arbitrary colourspaces and band formats to single-band 8-bit grayscale.

* NIF binding implemented over the vendored [nayuki/QR-Code-generator](https://github.com/nayuki/QR-Code-generator) (encoder, MIT) and [dlbeer/quirc](https://github.com/dlbeer/quirc) (decoder, ISC) C libraries. Both encoder and decoder run on dirty CPU schedulers and are safe under concurrent invocation.

* Precompiled NIF artefacts published for Linux (gnu/musl × x86_64/aarch64/ armv7), macOS (x86_64/arm64) and Windows (x86_64) via `cc_precompiler`.
