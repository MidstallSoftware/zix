{
  lib,
  mkMesonDerivation,

  doxygen,

  # Configuration Options

  version,
  nixVersion,
}:

let
  inherit (lib) fileset;
in

mkMesonDerivation (finalAttrs: {
  pname = "zix-internal-api-docs";
  inherit version nixVersion;

  workDir = ./.;
  fileset =
    let
      cpp = fileset.fileFilter (file: file.hasExt "cc" || file.hasExt "hh");
    in
    fileset.unions [
      ./.version
      ../../.version
      ./.zix-version
      ../../.zix-version
      ./meson.build
      ./doxygen.cfg.in
      # Source is not compiled, but still must be available for Doxygen
      # to gather comments.
      (cpp ../.)
    ];

  nativeBuildInputs = [
    doxygen
  ];

  preConfigure = ''
    chmod u+w ./.version
    echo ${finalAttrs.nixVersion} > ./.version

    chmod u+w ./.zix-version
    echo ${finalAttrs.version} > ./.zix-version
  '';

  postInstall = ''
    mkdir -p ''${!outputDoc}/nix-support
    echo "doc internal-api-docs $out/share/doc/nix/internal-api/html" >> ''${!outputDoc}/nix-support/hydra-build-products
  '';

  meta = {
    platforms = lib.platforms.all;
  };
})
