const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const linkage = b.option(std.builtin.LinkMode, "linkage", "The link mode of binaries");

    const config = b.addConfigHeader(.{
        .include_path = "config-util.hh",
    }, .{
        .HAVE_CLOSE_RANGE = 1,
        .HAVE_DECL_AT_SYMLINK_NOFOLLOW = 1,
        .HAVE_LIBCPUID = 1,
        .HAVE_PIPE2 = 1,
        .HAVE_POSIX_FALLOCATE = 1,
        .HAVE_STRSIGNAL = 1,
        .HAVE_SYSCONF = 1,
        .HAVE_UTIMENSAT = 1,
    });

    const libutil = std.Build.Step.Compile.create(b, .{
        .name = "nixutil",
        .kind = .lib,
        .linkage = linkage,
        .root_module = b.createModule(.{
            .root_source_file = b.path("libutil.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });

    libutil.addConfigHeader(config);

    libutil.addIncludePath(b.path("."));
    libutil.addIncludePath(b.path("widecharwidth"));

    if (target.result.os.tag == .windows) {
        libutil.addIncludePath(b.path("windows"));
        inline for (&.{
            "signals-impl.hh",
            "windows-async-pipe.hh",
            "windows-error.hh",
        }) |hdr| {
            libutil.installHeader(b.path("windows/" ++ hdr), "nix/" ++ hdr);
        }
    } else {
        libutil.addIncludePath(b.path("unix"));
        inline for (&.{
            "monitor-fd.hh",
            "signals-impl.hh",
        }) |hdr| {
            libutil.installHeader(b.path("unix/" ++ hdr), "nix/" ++ hdr);
        }
    }

    if (target.result.os.tag == .linux) {
        libutil.addIncludePath(b.path("linux"));
        inline for (&.{
            "cgroup.hh",
            "namespaces.hh",
        }) |hdr| {
            libutil.installHeader(b.path("linux/" ++ hdr), "nix/" ++ hdr);
        }
    }

    libutil.addCSourceFiles(.{
        .files = &.{
            "archive.cc",
            "args.cc",
            "canon-path.cc",
            "compression.cc",
            "compute-levels.cc",
            "config.cc",
            "config-global.cc",
            "current-process.cc",
            "english.cc",
            "environment-variables.cc",
            "error.cc",
            "executable-path.cc",
            "exit.cc",
            "experimental-features.cc",
            "file-content-address.cc",
            "file-descriptor.cc",
            "file-system.cc",
            "fs-sink.cc",
            "git.cc",
            "hash.cc",
            "hilite.cc",
            "json-utils.cc",
            "logging.cc",
            "memory-source-accessor.cc",
            "mounted-source-accessor.cc",
            "position.cc",
            "posix-source-accessor.cc",
            "references.cc",
            "serialise.cc",
            "signature/local-keys.cc",
            "signature/signer.cc",
            "source-accessor.cc",
            "source-path.cc",
            "strings.cc",
            "suggestions.cc",
            "tarfile.cc",
            "terminal.cc",
            "thread-pool.cc",
            "union-source-accessor.cc",
            "unix-domain-socket.cc",
            "url.cc",
            "users.cc",
            "util.cc",
            "xml-writer.cc",
        },
        .flags = &.{
            "--std=c++2a",
            b.fmt("-I{s}", .{std.mem.trimRight(u8, b.run(&.{ "pkg-config", "--variable=includedir", "boost" }), "\n")}),
        },
    });

    libutil.linkSystemLibrary("libarchive");
    libutil.linkSystemLibrary("libbrotlicommon");
    libutil.linkSystemLibrary("libbrotlidec");
    libutil.linkSystemLibrary("libbrotlienc");
    libutil.linkSystemLibrary("libsodium");
    libutil.linkSystemLibrary("boost");
    libutil.linkSystemLibrary("nlohmann_json");

    libutil.installHeader(config.getOutput(), "nix/config-util.hh");

    inline for (&.{
        "abstract-setting-to-json.hh",
        "ansicolor.hh",
        "archive.hh",
        "args.hh",
        "args/root.hh",
        "callback.hh",
        "canon-path.hh",
        "checked-arithmetic.hh",
        "chunked-vector.hh",
        "closure.hh",
        "comparator.hh",
        "compression.hh",
        "compute-levels.hh",
        "config-global.hh",
        "config-impl.hh",
        "config.hh",
        "current-process.hh",
        "english.hh",
        "environment-variables.hh",
        "error.hh",
        "exec.hh",
        "executable-path.hh",
        "exit.hh",
        "experimental-features.hh",
        "file-content-address.hh",
        "file-descriptor.hh",
        "file-path-impl.hh",
        "file-path.hh",
        "file-system.hh",
        "finally.hh",
        "fmt.hh",
        "fs-sink.hh",
        "git.hh",
        "hash.hh",
        "hilite.hh",
        "json-impls.hh",
        "json-utils.hh",
        "logging.hh",
        "lru-cache.hh",
        "memory-source-accessor.hh",
        "muxable-pipe.hh",
        "os-string.hh",
        "pool.hh",
        "position.hh",
        "posix-source-accessor.hh",
        "processes.hh",
        "ref.hh",
        "references.hh",
        "regex-combinators.hh",
        "repair-flag.hh",
        "serialise.hh",
        "signals.hh",
        "signature/local-keys.hh",
        "signature/signer.hh",
        "source-accessor.hh",
        "source-path.hh",
        "split.hh",
        "std-hash.hh",
        "strings.hh",
        "strings-inline.hh",
        "suggestions.hh",
        "sync.hh",
        "tarfile.hh",
        "terminal.hh",
        "thread-pool.hh",
        "topo-sort.hh",
        "types.hh",
        "unix-domain-socket.hh",
        "url-parts.hh",
        "url.hh",
        "users.hh",
        "util.hh",
        "variant-wrapper.hh",
        "xml-writer.hh",
    }) |hdr| {
        libutil.installHeader(b.path(hdr), "nix/" ++ hdr);
    }

    b.installArtifact(libutil);

    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.addWriteFile("nix-util.pc", b.fmt(
        \\prefix={s}
        \\libdir={s}
        \\includedir={s}
        \\
        \\Name: Nix
        \\Description: Nix Package Manager
        \\Version: 0.1.0
        \\Cflags: -I${{includedir}}/nix -std=c++2a
        \\Libs: -L${{libdir}} -lnixutil
    , .{
        b.getInstallPath(.prefix, ""),
        b.getInstallPath(.lib, ""),
        b.getInstallPath(.header, ""),
    })).getDirectory().path(b, "nix-util.pc"), .lib, "pkgconfig/nix-util.pc").step);
}
