zig = find_program('zig')
zig_target = target_machine.cpu_family() + '-'

if target_machine.system() == 'darwin'
  zig_target += target_machine.subsystem()
else
  zig_target += target_machine.system()
endif

zig_target += '-' + get_option('abi')

zig_base_args = [
  '--cache-dir', meson.current_build_dir() / 'zig-cache',
  '--global-cache-dir', meson.project_build_root() / 'zig-cache',
]

if get_option('debug') or get_option('optimization') == 'plain'
  zig_optimize = 'Debug'
elif get_option('optimization') == '2'
  zig_optimize = 'ReleaseFast'
elif get_option('optimization') == '3'
  zig_optimize = 'ReleaseSafe'
elif get_option('optimization') == 's'
  zig_optimize = 'ReleaseSmall'
endif

zig_args = zig_base_args + [
  '-target', zig_target,
  '-O', zig_optimize
]

zig_build_args = zig_base_args + [
  '-Dtarget=' + zig_target,
  '-Doptimize=' + zig_optimize,
]

if get_option('default_library') == 'shared'
  zig_build_args += ['-Dlinkage=dynamic']
elif get_option('default_library') == 'static'
  zig_build_args += ['-Dlinkage=static']
endif
