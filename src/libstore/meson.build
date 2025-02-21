project('nix-store',
  version : files('.zix-version'),
  default_options : [
    # TODO(Qyriad): increase the warning level
    'warning_level=1',
    'errorlogs=true', # Please print logs for tests that fail
    'localstatedir=/nix/var',
  ],
  meson_version : '>= 1.1',
  license : 'LGPL-2.1-or-later',
)

subdir('nix-meson-build-support/zig')

aws_s3 = dependency('aws-cpp-sdk-s3', required : false)
busybox = find_program(get_option('sandbox-shell'), required : false)

zig_build_args += [
  '-Dlog-path=' + get_option('log-dir'),
  '-Dstore-path=' + get_option('store-dir'),
  '-Dsandbox-shell=' + busybox.full_path(),
]

if get_option('embedded-sandbox-shell')
  zig_build_args += ['-Dembedded-sandbox-shell=true']
else
  zig_build_args += ['-Dembedded-sandbox-shell=false']
endif

if aws_s3.found()
  zig_build_args += ['-Ds3=true']
else
  zig_build_args += ['-Ds3=false']
endif

zig_target = custom_target('zig build',
  output: ['zig-out'],
  command: [zig, 'build', zig_build_args, '--prefix', meson.current_build_dir() / 'zig-out', '--build-file', meson.project_source_root() / 'build.zig'],
)

includedir = meson.current_build_dir() / 'zig-out' / 'include' / 'nix'
compile_args = ['-I' + includedir]

if host_machine.system() == 'linux'
  subdir('linux')
endif

if host_machine.system() == 'windows'
  subdir('windows')
else
  subdir('unix')
endif

install_subdir(meson.current_build_dir() / 'zig-out' / 'lib', install_dir: get_option('libdir'), strip_directory: true)
install_subdir(meson.current_build_dir() / 'zig-out' / 'include', install_dir: get_option('includedir'), strip_directory: true)

meson.override_dependency('nix-store', declare_dependency(
  compile_args: compile_args,
  link_args: ['-L' + meson.current_build_dir() / 'zig-out' / 'lib', '-lnixstore'],
  sources: [zig_target],
  variables: {
    'storedir': get_option('store-dir')
  }
))
