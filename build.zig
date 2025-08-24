const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // Dependencies
    //

    // Zalgebra: Linear algebra library for games and real-time graphics.
    const zalgebra_dep = b.dependency("zalgebra", .{ .target = target, .optimize = optimize });
    const zalgebra_mod = zalgebra_dep.module("zalgebra");

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

    const exe = b.addExecutable(.{
        .name = "exe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "phiz", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    //
    // Unit tests
    //

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const install_mod_tests = b.addInstallArtifact(mod_tests, .{ .dest_sub_path = "test" });

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    const install_test_step = b.step("install-test", "Install unit tests");
    install_test_step.dependOn(&install_mod_tests.step);
}
