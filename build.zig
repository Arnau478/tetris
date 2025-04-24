const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .shared = false,
    });
    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const options = b.addOptions();
    options.addOption(bool, "debug_info", b.option(bool, "debug-info", "Display debug info") orelse false);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("raylib", raylib);
    exe_mod.addImport("raygui", raygui);
    exe_mod.addOptions("build_options", options);

    const exe = b.addExecutable(.{
        .name = "tetris",
        .root_module = exe_mod,
        .use_lld = false,
    });
    exe.linkLibrary(raylib_artifact);

    b.installArtifact(exe);
}
