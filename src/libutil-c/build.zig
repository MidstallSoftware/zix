const std = @import("std");

fn readFile(b: *std.Build, path: []const u8) []const u8 {
    var file = b.build_root.handle.openFile(path, .{}) catch |err| std.debug.panic("Failed to open {s}: {}", .{ path, err });
    defer file.close();

    const meta = file.metadata() catch |err| std.debug.panic("Failed to get metadata for {s}: {}", .{ path, err });

    return file.readToEndAlloc(b.allocator, meta.size()) catch @panic("OOM");
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const linkage = b.option(std.builtin.LinkMode, "linkage", "The link mode of binaries");
    const fsys_libutil = b.systemIntegrationOption("nix-util", .{});

    const config = b.addConfigHeader(.{
        .include_path = "config-util.h",
    }, .{
        .PACKAGE_VERSION_NIX = std.mem.trimRight(u8, readFile(b, ".version"), "\n"),
        .PACKAGE_VERSION_ZIX = std.mem.trimRight(u8, readFile(b, ".zix-version"), "\n"),
    });

    const libutilc = std.Build.Step.Compile.create(b, .{
        .name = "nixutilc",
        .kind = .lib,
        .linkage = linkage,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });

    libutilc.addConfigHeader(config);

    libutilc.addIncludePath(b.path("."));

    libutilc.addCSourceFiles(.{
        .files = &.{
            "nix_api_util.cc",
        },
        .flags = &.{
            "--std=c++2a",
            b.fmt("-I{s}", .{std.mem.trimRight(u8, b.run(&.{ "pkg-config", "--variable=includedir", "boost" }), "\n")}),
        },
    });

    libutilc.installHeader(config.getOutput(), "nix/config-util.h");

    if (fsys_libutil) {
        libutilc.linkSystemLibrary("nix-util");
    } else {
        const libutil = b.dependency("nix-util", .{
            .target = target,
            .optimize = optimize,
            .linkage = linkage orelse .static,
        });

        libutilc.linkLibrary(libutil.artifact("nixutil"));

        for (libutil.artifact("nixutil").root_module.include_dirs.items) |hdr| {
            libutilc.root_module.include_dirs.append(b.allocator, hdr) catch @panic("OOM");
        }

        libutilc.linkSystemLibrary("libarchive");
        libutilc.linkSystemLibrary("boost");
        libutilc.linkSystemLibrary("nlohmann_json");
    }

    inline for (&.{
        "nix_api_util.h",
        "nix_api_util_internal.h",
    }) |hdr| {
        libutilc.installHeader(b.path(hdr), "nix/" ++ hdr);
    }

    b.installArtifact(libutilc);

    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.addWriteFile("nix-util-c.pc", b.fmt(
        \\prefix={s}
        \\libdir={s}
        \\includedir={s}
        \\
        \\Name: Nix
        \\Description: Nix Package Manager
        \\Version: 0.1.0
        \\Cflags: -I${{includedir}}/nix -std=c++2a
        \\Libs: -L${{libdir}} -lnixutil -lnixutilc
    , .{
        b.getInstallPath(.prefix, ""),
        b.getInstallPath(.lib, ""),
        b.getInstallPath(.header, ""),
    })).getDirectory().path(b, "nix-util-c.pc"), .lib, "pkgconfig/nix-util-c.pc").step);
}
