const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize_mode = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "minesweeper",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize_mode,
    });

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize_mode,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");

    exe.root_module.linkLibrary(sdl_lib);

    exe.root_module.addAnonymousImport("sprite_sheet", .{ .root_source_file = b.path("res/tile.bmp") });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/minesweeper/test.zig"),
        .target = target,
        .optimize = optimize_mode,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
