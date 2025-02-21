project('nix-util-c',
  version : files('.zix-version'),
  default_options : [
    # TODO(Qyriad): increase the warning level
    'warning_level=1',
    'errorlogs=true', # Please print logs for tests that fail
  ],
  meson_version : '>= 1.1',
  license : 'LGPL-2.1-or-later',
)


subdir('nix-meson-build-support/zig')

zig_target = custom_target('zig build',
  output: ['zig-out'],
  command: [zig, 'build', zig_build_args, '--prefix', meson.current_build_dir() / 'zig-out', '--build-file', meson.project_source_root() / 'build.zig'],
)

includedir = meson.current_build_dir() / 'zig-out' / 'include' / 'nix'
compile_args = ['-I' + includedir]

install_subdir(meson.current_build_dir() / 'zig-out' / 'lib', install_dir: get_option('libdir'), strip_directory: true)
install_subdir(meson.current_build_dir() / 'zig-out' / 'include', install_dir: get_option('includedir'), strip_directory: true)

meson.override_dependency('nix-util-c', declare_dependency(
  compile_args: compile_args,
  link_args: ['-L' + meson.current_build_dir() / 'zig-out' / 'lib', '-lnixutilc'],
  sources: [zig_target],
))
