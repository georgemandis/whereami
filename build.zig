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

    // Simple run step for initial development (runs bare binary).
    // Task 5 will replace this with a macOS .app bundle-based run step.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run whereami");
    run_step.dependOn(&run_cmd.step);
}
