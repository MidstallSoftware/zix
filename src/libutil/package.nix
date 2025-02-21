{
  lib,
  stdenv,
  mkZigLibrary,

  boost,
  brotli,
  libarchive,
  libsodium,
  nlohmann_json,

  # Configuration Options

  version,
  nixVersion,
}:

let
  inherit (lib) fileset;
in

mkZigLibrary (finalAttrs: {
  pname = "zix-util";
  inherit version nixVersion;

  workDir = ./.;
  fileset = fileset.unions [
    ../../nix-meson-build-support
    ./nix-meson-build-support
    ../../.version
    ./.version
    ../../.zix-version
    ./.zix-version
    ./widecharwidth
    (fileset.fileFilter (file: file.hasExt "cc") ./.)
    (fileset.fileFilter (file: file.hasExt "hh") ./.)
    (fileset.fileFilter (file: file.hasExt "zig") ./.)
  ];

  buildInputs = [
    brotli
    libsodium
  ];

  propagatedBuildInputs = [
    boost
    libarchive
    nlohmann_json
  ];

  postInstall = ''
    substituteInPlace $out/lib/pkgconfig/nix-util.pc \
      --replace-fail "includedir=$out" "includedir=$dev"
  '';

  meta = {
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  };

})
