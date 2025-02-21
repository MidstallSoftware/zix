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
    const store_path = b.option([]const u8, "store-path", "Path to the nix store") orelse "/nix/store";
    const state_path = b.option([]const u8, "state-path", "Path to store the state of nix") orelse "/nix/var/nix";
    const log_path = b.option([]const u8, "log-path", "Path to store the logs") orelse b.pathJoin(&.{ state_path, "log", "nix" });
    const conf_path = b.option([]const u8, "conf-path", "Path to the config") orelse b.getInstallPath(.prefix, "etc/nix");
    const enable_s3 = b.option(bool, "s3", "Enable S3") orelse false;
    const sandbox_shell = b.option([]const u8, "sandbox-shell", "Path to a statically-linked shell to use as /bin/sh in sandboxes (usually busybox)");
    const embedded_sandbox_shell = b.option(bool, "embedded-sandbox-shell", "Include the sandbox shell in the Nix binary") orelse (linkage == .static);
    const fsys_libutil = b.systemIntegrationOption("nix-util", .{});

    const config = b.addConfigHeader(.{
        .include_path = "config-store.hh",
    }, .{
        .CAN_LINK_SYMLINK = 1,
        .ENABLE_S3 = @as(i64, @intFromBool(enable_s3)),
        .HAVE_ACL_SUPPORT = 1,
        .HAVE_LCHOWN = 1,
        .HAVE_SECCOMP = @as(i64, @intFromBool(target.result.os.tag == .linux)),
        .HAVE_STATVFS = 1,
        .PACKAGE_VERSION_NIX = std.mem.trimRight(u8, readFile(b, ".version"), "\n"),
        .PACKAGE_VERSION_ZIX = std.mem.trimRight(u8, readFile(b, ".zix-version"), "\n"),
        .SYSTEM = b.fmt("{s}-{s}", .{
            @tagName(target.result.cpu.arch),
            @tagName(target.result.os.tag),
        }),
    });

    const gen_headers = b.addWriteFiles();

    if (sandbox_shell) |value| {
        if (embedded_sandbox_shell) {
            config.addValues(.{
                .HAVE_EMBEDDED_SANDBOX_SHELL = 1,
                .SANDBOX_SHELL = "__embedded_sandbox_shell__",
            });

            var hexdump = std.ArrayList(u8).init(b.allocator);
            defer hexdump.deinit();

            for (readFile(b, value)) |x| {
                hexdump.writer().print("0x{x},\n", .{x}) catch @panic("OOM");
            }

            _ = gen_headers.add("embedded-sandbox-shell.gen.hh", hexdump.items);
        } else {
            config.addValues(.{
                .SANDBOX_SHELL = value,
            });
        }
    }
    _ = gen_headers.add("schema.sql.gen.hh", b.fmt("R\"__NIX_STR(\n{s}\n)__NIX_STR\"", .{readFile(b, "schema.sql")}));
    _ = gen_headers.add("ca-specific-schema.sql.gen.hh", b.fmt("R\"__NIX_STR(\n{s}\n)__NIX_STR\"", .{readFile(b, "ca-specific-schema.sql")}));

    const libstore = std.Build.Step.Compile.create(b, .{
        .name = "nixstore",
        .kind = .lib,
        .linkage = linkage,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });

    libstore.addIncludePath(gen_headers.getDirectory());

    {
        var iter = config.values.iterator();
        while (iter.next()) |entry| {
            libstore.root_module.addCMacro(entry.key_ptr.*, switch (entry.value_ptr.*) {
                .undef, .defined => continue,
                .boolean => |x| b.fmt("{}", .{@intFromBool(x)}),
                .int => |i| b.fmt("{}", .{i}),
                .ident => |d| b.fmt("{s}", .{d}),
                .string => |s| b.fmt("\"{s}\"", .{s}),
            });
        }
    }

    libstore.root_module.addCMacro("NIX_PREFIX", b.fmt("\"{s}\"", .{b.getInstallPath(.prefix, "")}));
    libstore.root_module.addCMacro("NIX_STORE_DIR", b.fmt("\"{s}\"", .{store_path}));
    libstore.root_module.addCMacro("NIX_DATA_DIR", b.fmt("\"{s}\"", .{b.getInstallPath(.prefix, "share")}));
    libstore.root_module.addCMacro("NIX_STATE_DIR", b.fmt("\"{s}\"", .{state_path}));
    libstore.root_module.addCMacro("NIX_LOG_DIR", b.fmt("\"{s}\"", .{log_path}));
    libstore.root_module.addCMacro("NIX_CONF_DIR", b.fmt("\"{s}\"", .{conf_path}));
    libstore.root_module.addCMacro("NIX_MAN_DIR", b.fmt("\"{s}\"", .{b.getInstallPath(.prefix, "share/man")}));

    libstore.addConfigHeader(config);
    libstore.addIncludePath(b.path("."));
    libstore.addIncludePath(b.path("build"));

    if (target.result.os.tag == .windows) {
        libstore.addIncludePath(b.path("windows"));
        libstore.addCSourceFile(.{
            .file = b.path("windows/pathlocks.cc"),
            .flags = &.{
                "--std=c++2a",
                b.fmt("-I{s}", .{std.mem.trimRight(u8, b.run(&.{ "pkg-config", "--variable=includedir", "boost" }), "\n")}),
            },
        });
    } else {
        libstore.addIncludePath(b.path("unix"));
        libstore.addIncludePath(b.path("unix/build"));
        libstore.addCSourceFiles(.{
            .files = &.{
                "unix/build/child.cc",
                "unix/build/hook-instance.cc",
                "unix/build/local-derivation-goal.cc",
                "unix/pathlocks.cc",
                "unix/user-lock.cc",
            },
            .flags = &.{
                "--std=c++2a",
                b.fmt("-I{s}", .{std.mem.trimRight(u8, b.run(&.{ "pkg-config", "--variable=includedir", "boost" }), "\n")}),
            },
        });

        inline for (&.{
            "build/child.hh",
            "build/hook-instance.hh",
            "build/local-derivation-goal.hh",
            "user-lock.hh",
        }) |hdr| {
            libstore.installHeader(b.path("unix/" ++ hdr), "nix/" ++ hdr);
        }
    }

    if (target.result.os.tag == .linux) {
        libstore.addIncludePath(b.path("linux"));
        libstore.addCSourceFiles(.{
            .files = &.{
                "linux/personality.cc",
            },
            .flags = &.{
                "--std=c++2a",
                b.fmt("-I{s}", .{std.mem.trimRight(u8, b.run(&.{ "pkg-config", "--variable=includedir", "boost" }), "\n")}),
            },
        });

        inline for (&.{
            "fchmodat2-compat.hh",
            "personality.hh",
        }) |hdr| {
            libstore.installHeader(b.path("linux/" ++ hdr), "nix/" ++ hdr);
        }
    }

    libstore.installHeader(config.getOutput(), "nix/config-store.hh");

    libstore.addCSourceFiles(.{
        .files = &.{
            "binary-cache-store.cc",
            "build-result.cc",
            "build/derivation-goal.cc",
            "build/derivation-creation-and-realisation-goal.cc",
            "build/drv-output-substitution-goal.cc",
            "build/entry-points.cc",
            "build/goal.cc",
            "build/substitution-goal.cc",
            "build/worker.cc",
            "builtins/buildenv.cc",
            "builtins/fetchurl.cc",
            "builtins/unpack-channel.cc",
            "common-protocol.cc",
            "common-ssh-store-config.cc",
            "content-address.cc",
            "daemon.cc",
            "derivations.cc",
            "derivation-options.cc",
            "derived-path-map.cc",
            "derived-path.cc",
            "downstream-placeholder.cc",
            "dummy-store.cc",
            "export-import.cc",
            "filetransfer.cc",
            "gc.cc",
            "globals.cc",
            "http-binary-cache-store.cc",
            "indirect-root-store.cc",
            "keys.cc",
            "legacy-ssh-store.cc",
            "local-binary-cache-store.cc",
            "local-fs-store.cc",
            "local-overlay-store.cc",
            "local-store.cc",
            "log-store.cc",
            "machines.cc",
            "make-content-addressed.cc",
            "misc.cc",
            "names.cc",
            "nar-accessor.cc",
            "nar-info-disk-cache.cc",
            "nar-info.cc",
            "optimise-store.cc",
            "outputs-spec.cc",
            "parsed-derivations.cc",
            "path-info.cc",
            "path-references.cc",
            "path-with-outputs.cc",
            "path.cc",
            "pathlocks.cc",
            "posix-fs-canonicalise.cc",
            "profiles.cc",
            "realisation.cc",
            "remote-fs-accessor.cc",
            "remote-store.cc",
            "s3-binary-cache-store.cc",
            "serve-protocol-connection.cc",
            "serve-protocol.cc",
            "sqlite.cc",
            "ssh-store.cc",
            "ssh.cc",
            "store-api.cc",
            "store-reference.cc",
            "uds-remote-store.cc",
            "worker-protocol-connection.cc",
            "worker-protocol.cc",
        },
        .flags = &.{
            "--std=c++2a",
            b.fmt("-I{s}", .{std.mem.trimRight(u8, b.run(&.{ "pkg-config", "--variable=includedir", "boost" }), "\n")}),
        },
    });

    libstore.linkSystemLibrary("libcurl");
    libstore.linkSystemLibrary("sqlite3");

    if (enable_s3) {
        libstore.linkSystemLibrary("aws-cpp-sdk-s3");
    }

    if (target.result.os.tag == .linux) {
        libstore.linkSystemLibrary("libseccomp");
    }

    if (fsys_libutil) {
        libstore.linkSystemLibrary("nix-util");
    } else {
        const libutil = b.dependency("nix-util", .{
            .target = target,
            .optimize = optimize,
            .linkage = linkage orelse .static,
        });

        libstore.linkLibrary(libutil.artifact("nixutil"));

        for (libutil.artifact("nixutil").root_module.include_dirs.items) |hdr| {
            libstore.root_module.include_dirs.append(b.allocator, hdr) catch @panic("OOM");
        }

        libstore.linkSystemLibrary("libarchive");
        libstore.linkSystemLibrary("boost");
        libstore.linkSystemLibrary("nlohmann_json");
    }

    inline for (&.{
        "binary-cache-store.hh",
        "build-result.hh",
        "build/derivation-goal.hh",
        "build/derivation-creation-and-realisation-goal.hh",
        "build/drv-output-substitution-goal.hh",
        "build/goal.hh",
        "build/substitution-goal.hh",
        "build/worker.hh",
        "builtins.hh",
        "builtins/buildenv.hh",
        "common-protocol-impl.hh",
        "common-protocol.hh",
        "common-ssh-store-config.hh",
        "content-address.hh",
        "daemon.hh",
        "derivations.hh",
        "derivation-options.hh",
        "derived-path-map.hh",
        "derived-path.hh",
        "downstream-placeholder.hh",
        "filetransfer.hh",
        "gc-store.hh",
        "globals.hh",
        "http-binary-cache-store.hh",
        "indirect-root-store.hh",
        "keys.hh",
        "legacy-ssh-store.hh",
        "length-prefixed-protocol-helper.hh",
        "local-binary-cache-store.hh",
        "local-fs-store.hh",
        "local-overlay-store.hh",
        "local-store.hh",
        "log-store.hh",
        "machines.hh",
        "make-content-addressed.hh",
        "names.hh",
        "nar-accessor.hh",
        "nar-info-disk-cache.hh",
        "nar-info.hh",
        "outputs-spec.hh",
        "parsed-derivations.hh",
        "path-info.hh",
        "path-references.hh",
        "path-regex.hh",
        "path-with-outputs.hh",
        "path.hh",
        "pathlocks.hh",
        "posix-fs-canonicalise.hh",
        "profiles.hh",
        "realisation.hh",
        "remote-fs-accessor.hh",
        "remote-store-connection.hh",
        "remote-store.hh",
        "s3-binary-cache-store.hh",
        "s3.hh",
        "ssh-store.hh",
        "serve-protocol-connection.hh",
        "serve-protocol-impl.hh",
        "serve-protocol.hh",
        "sqlite.hh",
        "ssh.hh",
        "store-api.hh",
        "store-cast.hh",
        "store-dir-config.hh",
        "store-reference.hh",
        "uds-remote-store.hh",
        "worker-protocol-connection.hh",
        "worker-protocol-impl.hh",
        "worker-protocol.hh",
    }) |hdr| {
        libstore.installHeader(b.path(hdr), "nix/" ++ hdr);
    }

    b.installArtifact(libstore);

    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.addWriteFile("nix-store.pc", b.fmt(
        \\prefix={s}
        \\libdir={s}
        \\includedir={s}
        \\storedir={s}
        \\
        \\Name: Nix
        \\Description: Nix Package Manager
        \\Version: 0.1.0
        \\Cflags: -I${{includedir}}/nix -std=c++2a
        \\Libs: -L${{libdir}} -lnixstore
    , .{
        b.getInstallPath(.prefix, ""),
        b.getInstallPath(.lib, ""),
        b.getInstallPath(.header, ""),
        store_path,
    })).getDirectory().path(b, "nix-store.pc"), .lib, "pkgconfig/nix-store.pc").step);
}
