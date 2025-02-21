{
  lib,
  inputs,
  devFlake,
}:

{ pkgs }:

pkgs.zixComponents.nix-util.overrideAttrs (
  attrs:

  let
    stdenv = pkgs.zixDependencies.stdenv;
    buildCanExecuteHost = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
    modular = devFlake.getSystem stdenv.buildPlatform.system;
    transformFlag =
      prefix: flag:
      assert builtins.isString flag;
      let
        rest = builtins.substring 2 (builtins.stringLength flag) flag;
      in
      "-D${prefix}:${rest}";
    havePerl = stdenv.buildPlatform == stdenv.hostPlatform && stdenv.hostPlatform.isUnix;
    ignoreCrossFile = flags: builtins.filter (flag: !(lib.strings.hasInfix "cross-file" flag)) flags;
  in
  {
    pname = "shell-for-" + attrs.pname;

    # Remove the version suffix to avoid unnecessary attempts to substitute in nix develop
    version = lib.fileContents ../.version;
    name = attrs.pname;

    installFlags = "sysconfdir=$(out)/etc";
    shellHook = ''
      PATH=$prefix/bin:$PATH
      unset PYTHONPATH
      export MANPATH=$out/share/man:$MANPATH

      # Make bash completion work.
      XDG_DATA_DIRS+=:$out/share

      # Make the default phases do the right thing.
      # FIXME: this wouldn't be needed if the ninja package set buildPhase() instead of $buildPhase.
      # FIXME: mesonConfigurePhase shouldn't cd to the build directory. It would be better to pass '-C <dir>' to ninja.

      cdToBuildDir() {
          if [[ ! -e build.ninja ]]; then
              cd build
          fi
      }

      configurePhase() {
          mesonConfigurePhase
      }

      buildPhase() {
          cdToBuildDir
          ninjaBuildPhase
      }

      checkPhase() {
          cdToBuildDir
          mesonCheckPhase
      }

      installPhase() {
          cdToBuildDir
          ninjaInstallPhase
      }
    '';

    # We use this shell with the local checkout, not unpackPhase.
    src = null;

    env = {
      # Needed for Meson to find Boost.
      # https://github.com/NixOS/nixpkgs/issues/86131.
      BOOST_INCLUDEDIR = "${lib.getDev pkgs.zixDependencies.boost}/include";
      BOOST_LIBRARYDIR = "${lib.getLib pkgs.zixDependencies.boost}/lib";
      # For `make format`, to work without installing pre-commit
      _NIX_PRE_COMMIT_HOOKS_CONFIG = "${(pkgs.formats.yaml { }).generate "pre-commit-config.yaml"
        modular.pre-commit.settings.rawConfig
      }";
    };

    mesonFlags =
      map (transformFlag "libutil") (ignoreCrossFile pkgs.zixComponents.nix-util.mesonFlags)
      ++ map (transformFlag "libstore") (ignoreCrossFile pkgs.zixComponents.nix-store.mesonFlags)
      ++ map (transformFlag "libfetchers") (ignoreCrossFile pkgs.zixComponents.nix-fetchers.mesonFlags)
      ++ lib.optionals havePerl (
        map (transformFlag "perl") (ignoreCrossFile pkgs.zixComponents.nix-perl-bindings.mesonFlags)
      )
      ++ map (transformFlag "libexpr") (ignoreCrossFile pkgs.zixComponents.nix-expr.mesonFlags)
      ++ map (transformFlag "libcmd") (ignoreCrossFile pkgs.zixComponents.nix-cmd.mesonFlags);

    nativeBuildInputs =
      attrs.nativeBuildInputs or [ ]
      ++ pkgs.zixComponents.nix-util.nativeBuildInputs
      ++ pkgs.zixComponents.nix-store.nativeBuildInputs
      ++ pkgs.zixComponents.nix-fetchers.nativeBuildInputs
      ++ pkgs.zixComponents.nix-expr.nativeBuildInputs
      ++ lib.optionals havePerl pkgs.zixComponents.nix-perl-bindings.nativeBuildInputs
      ++ lib.optionals buildCanExecuteHost pkgs.zixComponents.nix-manual.externalNativeBuildInputs
      ++ pkgs.zixComponents.nix-internal-api-docs.nativeBuildInputs
      ++ pkgs.zixComponents.nix-external-api-docs.nativeBuildInputs
      ++ pkgs.zixComponents.nix-functional-tests.externalNativeBuildInputs
      ++ lib.optional (
        !buildCanExecuteHost
        # Hack around https://github.com/nixos/nixpkgs/commit/bf7ad8cfbfa102a90463433e2c5027573b462479
        && !(stdenv.hostPlatform.isWindows && stdenv.buildPlatform.isDarwin)
        && stdenv.hostPlatform.emulatorAvailable pkgs.buildPackages
        && lib.meta.availableOn stdenv.buildPlatform (stdenv.hostPlatform.emulator pkgs.buildPackages)
      ) pkgs.buildPackages.mesonEmulatorHook
      ++ [
        pkgs.buildPackages.cmake
        pkgs.buildPackages.shellcheck
        pkgs.buildPackages.changelog-d
        pkgs.buildPackages.nixfmt-rfc-style
        modular.pre-commit.settings.package
        (pkgs.writeScriptBin "pre-commit-hooks-install" modular.pre-commit.settings.installationScript)
      ]
      # TODO: Remove the darwin check once
      # https://github.com/NixOS/nixpkgs/pull/291814 is available
      ++ lib.optional (stdenv.cc.isClang && !stdenv.buildPlatform.isDarwin) pkgs.buildPackages.bear
      ++ lib.optional (stdenv.cc.isClang && stdenv.hostPlatform == stdenv.buildPlatform) (
        lib.hiPrio pkgs.buildPackages.clang-tools
      );

    buildInputs =
      attrs.buildInputs or [ ]
      ++ pkgs.zixComponents.nix-util.buildInputs
      ++ pkgs.zixComponents.nix-store.buildInputs
      ++ pkgs.zixComponents.nix-store-tests.externalBuildInputs
      ++ pkgs.zixComponents.nix-fetchers.buildInputs
      ++ pkgs.zixComponents.nix-expr.buildInputs
      ++ pkgs.zixComponents.nix-expr.externalPropagatedBuildInputs
      ++ pkgs.zixComponents.nix-cmd.buildInputs
      ++ lib.optionals havePerl pkgs.zixComponents.nix-perl-bindings.externalBuildInputs
      ++ lib.optional havePerl pkgs.perl;
  }
)
