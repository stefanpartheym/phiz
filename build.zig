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

    // Public math module (wraps zalgebra)
    const math_mod = b.addModule(
        "math",
        .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/math/mod.zig"),
        },
    );
    math_mod.addImport("zalgebra", zalgebra_mod);

    // Public library module
    const mod = b.addModule("phiz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    mod.addImport("m", math_mod);

    //
    // Examples
    //

    const example_platformer = Example{
        .source = "src/examples/platformer.zig",
        .target = target,
        .optimize = optimize,
        .raylib_mod = raylib_mod,
        .raylib_lib = raylib_lib,
        .main_mod = mod,
    };
    example_platformer.add(b, "platformer");

    const example_topdown = Example{
        .source = "src/examples/topdown.zig",
        .target = target,
        .optimize = optimize,
        .raylib_mod = raylib_mod,
        .raylib_lib = raylib_lib,
        .main_mod = mod,
    };
    example_topdown.add(b, "topdown");

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

const Example = struct {
    source: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    raylib_mod: *std.Build.Module,
    raylib_lib: *std.Build.Step.Compile,
    main_mod: *std.Build.Module,

    pub fn add(self: @This(), b: *std.Build, comptime name: []const u8) void {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(self.source),
            .target = self.target,
            .optimize = self.optimize,
            // Link against libc for raylib.
            .link_libc = true,
        });
        exe_mod.addImport("raylib", self.raylib_mod);
        exe_mod.addImport("phiz", self.main_mod);
        exe_mod.linkLibrary(self.raylib_lib);

        const exe = b.addExecutable(.{ .name = "example-" ++ name, .root_module = exe_mod });
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step("run-" ++ name, "Run the " ++ name ++ " example");
        run_step.dependOn(&run_cmd.step);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    }
};
