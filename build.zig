const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const target_os = target.result.os.tag;

    const location_mod = b.createModule(.{
        .root_source_file = b.path("src/location.zig"),
        .target = target,
        .optimize = optimize,
    });

    switch (target_os) {
        .macos => {
            location_mod.linkSystemLibrary("objc", .{});
            location_mod.linkFramework("CoreLocation", .{});
            location_mod.linkFramework("Foundation", .{});
        },
        else => {},
    }

    const exe = b.addExecutable(.{
        .name = "whereami",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "location", .module = location_mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run whereami");

    if (target_os == .macos) {
        // macOS .app bundle for location permissions
        const bundle_step = b.step("bundle", "Create macOS .app bundle with ad-hoc signing");

        // Create .app directory structure and Info.plist
        const mkdir_and_plist = b.addSystemCommand(&.{
            "sh", "-c",
            \\mkdir -p zig-out/whereami.app/Contents/MacOS && \
            \\cat > zig-out/whereami.app/Contents/Info.plist << 'PLIST'
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            \\<plist version="1.0">
            \\<dict>
            \\    <key>CFBundleIdentifier</key>
            \\    <string>com.whereami.cli</string>
            \\    <key>CFBundleExecutable</key>
            \\    <string>whereami</string>
            \\    <key>CFBundleName</key>
            \\    <string>whereami</string>
            \\    <key>NSLocationUsageDescription</key>
            \\    <string>whereami needs your location to display coordinates.</string>
            \\    <key>NSLocationWhenInUseUsageDescription</key>
            \\    <string>whereami needs your location to display coordinates.</string>
            \\</dict>
            \\</plist>
            \\PLIST
        });
        mkdir_and_plist.step.dependOn(b.getInstallStep());

        // Copy binary into bundle
        const copy_binary = b.addSystemCommand(&.{
            "cp", "zig-out/bin/whereami", "zig-out/whereami.app/Contents/MacOS/whereami",
        });
        copy_binary.step.dependOn(&mkdir_and_plist.step);

        // Ad-hoc sign (requires Xcode Command Line Tools; fails with clear error if missing)
        const codesign = b.addSystemCommand(&.{
            "codesign", "--force", "--sign", "-", "zig-out/whereami.app",
        });
        codesign.step.dependOn(&copy_binary.step);

        bundle_step.dependOn(&codesign.step);

        // zig build run uses the bundle binary on macOS
        const bundle_run = b.addSystemCommand(&.{
            "zig-out/whereami.app/Contents/MacOS/whereami",
        });
        bundle_run.step.dependOn(&codesign.step);
        if (b.args) |args| {
            for (args) |arg| {
                bundle_run.addArg(arg);
            }
        }
        run_step.dependOn(&bundle_run.step);
    } else {
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        run_step.dependOn(&run_cmd.step);
    }
}
