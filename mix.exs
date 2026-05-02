defmodule ImageQRCode.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/elixir-image/image_qrcode"

  def project do
    [
      app: :image_qrcode,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:elixir_make] ++ Mix.compilers(),
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        flags: [:unmatched_returns, :error_handling, :underspecs]
      ],

      # elixir_make / cc_precompiler configuration
      make_targets: ["all"],
      make_clean: ["clean"],
      make_precompiler: {:nif, CCPrecompiler},
      make_precompiler_url: "#{@source_url}/releases/download/v#{@version}/@{artefact_filename}",
      make_precompiler_filename: "image_qrcode_nif",
      # Currently OTP 26, 27, and 28 all expose NIF ABI 2.17 — there is no
      # NIF 2.18 in any released OTP yet. Add "2.18" here (and a matching
      # job to .github/workflows/precompile.yml) once a future OTP bumps it.
      make_precompiler_nif_versions: [versions: ["2.17"]],
      cc_precompiler: cc_precompiler()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:vix, "~> 0.27"},
      {:elixir_make, "~> 0.8", runtime: false},
      {:cc_precompiler, "~> 0.1", runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    """
    QR code encoding and decoding for the Image library, implemented as a NIF
    over the vendored nayuki/QR-Code-generator (encoder, MIT) and dlbeer/quirc
    (decoder, ISC) C libraries.
    """
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      # Project license is Apache-2.0; the tarball additionally vendors
      # MIT (nayuki/QR-Code-generator) and ISC (dlbeer/quirc) sources.
      licenses: ["Apache-2.0", "MIT", "ISC"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/v#{@version}/CHANGELOG.md",
        "nayuki/QR-Code-generator" => "https://github.com/nayuki/QR-Code-generator",
        "dlbeer/quirc" => "https://github.com/dlbeer/quirc"
      },
      files: [
        "lib",
        "c_src/qrcode_nif.c",
        "c_src/Makefile",
        "c_src/nayuki/qrcodegen.c",
        "c_src/nayuki/qrcodegen.h",
        "c_src/quirc/quirc.c",
        "c_src/quirc/quirc.h",
        "c_src/quirc/quirc_internal.h",
        "c_src/quirc/decode.c",
        "c_src/quirc/identify.c",
        "c_src/quirc/version_db.c",
        "c_src/quirc/LICENSE",
        "Makefile",
        "checksum.exs",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "logo.jpg",
        ".formatter.exs"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "logo.jpg",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      formatters: ["html"],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp cc_precompiler do
    [
      cleanup: "clean",
      compilers: %{
        {:unix, :linux} => %{
          "x86_64-linux-gnu" => "x86_64-linux-gnu-",
          "aarch64-linux-gnu" => "aarch64-linux-gnu-",
          "armv7l-linux-gnueabihf" => "arm-linux-gnueabihf-",
          "x86_64-linux-musl" => "x86_64-linux-musl-",
          "aarch64-linux-musl" => "aarch64-linux-musl-"
        },
        {:unix, :darwin} => %{
          "x86_64-apple-darwin" => {
            "gcc",
            "g++",
            "<%= cc %> -arch x86_64",
            "<%= cxx %> -arch x86_64"
          },
          "aarch64-apple-darwin" => {
            "gcc",
            "g++",
            "<%= cc %> -arch arm64",
            "<%= cxx %> -arch arm64"
          }
        },
        {:win32, :nt} => %{}
      }
    ]
  end
end
