{
  lib,
  mkZigLibrary,

  nix-util,

  # Configuration Options

  version,
  nixVersion,
}:

let
  inherit (lib) fileset;
in

mkZigLibrary (finalAttrs: {
  pname = "zix-util-c";
  inherit version nixVersion;

  workDir = ./.;
  fileset = fileset.unions [
    ../libutil
    ../../nix-meson-build-support
    ./nix-meson-build-support
    ../../.version
    ./.version
    ../../.zix-version
    ./.zix-version
    ./meson.build
    ./meson.options
    (fileset.fileFilter (file: file.hasExt "cc") ./.)
    (fileset.fileFilter (file: file.hasExt "hh") ./.)
    (fileset.fileFilter (file: file.hasExt "h") ./.)
    (fileset.fileFilter (file: file.hasExt "zig") ./.)
    (fileset.fileFilter (file: file.hasExt "zon") ./.)
  ];

  propagatedBuildInputs = [
    nix-util
  ];

  zigBuildFlags = [
    "-fsys=nix-util"
  ];

  postInstall = ''
    substituteInPlace $out/lib/pkgconfig/nix-util-c.pc \
      --replace-fail "includedir=$out" "includedir=$dev"
  '';

  meta = {
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  };

})
