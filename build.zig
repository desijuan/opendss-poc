const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    // Tested to work with Zig 0.12.0
    if (builtin.zig_version.minor < 12)
        @compileError("Please use Zig version 0.12 or higher");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "opendss",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.addIncludePath(.{ .path = "opendss" });
    exe.addLibraryPath(.{ .path = "opendss" });
    exe.linkSystemLibrary("dss_capi");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
