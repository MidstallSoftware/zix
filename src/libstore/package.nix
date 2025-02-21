{
  lib,
  stdenv,
  mkZigLibrary,

  unixtools,
  darwin,

  nix-util,
  boost,
  curl,
  aws-sdk-cpp,
  libseccomp,
  nlohmann_json,
  sqlite,

  busybox-sandbox-shell ? null,

  # Configuration Options

  version,
  nixVersion,

  embeddedSandboxShell ? stdenv.hostPlatform.isStatic,
}:

let
  inherit (lib) fileset;
in

mkZigLibrary (finalAttrs: {
  pname = "zix-store";
  inherit version nixVersion;

  workDir = ./.;
  fileset = fileset.unions [
    ../../nix-meson-build-support
    ./nix-meson-build-support
    ../../.version
    ./.version
    ../../.zix-version
    ./.zix-version
    ./meson.build
    ./meson.options
    ./linux/meson.build
    ./unix/meson.build
    ./windows/meson.build
    (fileset.fileFilter (file: file.hasExt "cc") ./.)
    (fileset.fileFilter (file: file.hasExt "hh") ./.)
    (fileset.fileFilter (file: file.hasExt "sb") ./.)
    (fileset.fileFilter (file: file.hasExt "md") ./.)
    (fileset.fileFilter (file: file.hasExt "sql") ./.)
    (fileset.fileFilter (file: file.hasExt "zig") ./.)
    (fileset.fileFilter (file: file.hasExt "zon") ./.)
  ];

  nativeBuildInputs = lib.optional embeddedSandboxShell unixtools.hexdump;

  buildInputs =
    [
      boost
      curl
      sqlite
    ]
    ++ lib.optional stdenv.hostPlatform.isLinux libseccomp
    # There have been issues building these dependencies
    ++ lib.optional stdenv.hostPlatform.isDarwin darwin.apple_sdk.libs.sandbox;

  propagatedBuildInputs = [
    nix-util
    nlohmann_json
  ];

  zigBuildFlags = [
    "-fsys=nix-util"
    "-Dembedded-sandbox-shell=${lib.boolToString embeddedSandboxShell}"
  ] ++ lib.optional stdenv.hostPlatform.isLinux "-Dsandbox-shell=${busybox-sandbox-shell}/bin/busybox";

  postInstall = ''
    substituteInPlace $out/lib/pkgconfig/nix-store.pc \
      --replace-fail "includedir=$out" "includedir=$dev"
  '';

  meta = {
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  };

})
