const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = .{ .target = target, .optimize = optimize };

    //
    // Dependencies
    //

    // Zalgebra: Linear algebra library for games and real-time graphics.
    const zalgebra_dep = b.dependency("zalgebra", options);
    const zalgebra_mod = zalgebra_dep.module("zalgebra");
    // Raylib: Graphics library.
    // This is only used for the example.
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = .X11,
    });
    const raylib_mod = raylib_dep.module("raylib");
    const raylib_lib = raylib_dep.artifact("raylib");

    //
    // Modules
    //

    // Internal math module (wraps zalgebra)
    const math_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/math/mod.zig"),
    });
    math_mod.addImport("zalgebra", zalgebra_mod);

    // Public library module
    const mod = b.addModule("phiz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    mod.addImport("m", math_mod);

    //
    // Executable
    //

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // Link against libc for raylib.
        .link_libc = true,
    });
    exe_mod.addImport("raylib", raylib_mod);
    exe_mod.addImport("phiz", mod);
    exe_mod.linkLibrary(raylib_lib);

    const exe = b.addExecutable(.{ .name = "exe", .root_module = exe_mod });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    //
    // Unit tests
    //

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("m", math_mod);

    const mod_tests = b.addTest(.{ .root_module = test_mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const install_mod_tests = b.addInstallArtifact(
        mod_tests,
        .{ .dest_sub_path = "test" },
    );

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    const install_test_step = b.step("install-test", "Install unit tests");
    install_test_step.dependOn(&install_mod_tests.step);
}
