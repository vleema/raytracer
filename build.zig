const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("raytracer", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "raytracer",
        .root_module = mod,
        .use_llvm = true,
    });

    b.installArtifact(exe);

    // Setup zig build run that runs the main module executable.
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run.step);

    // Pass args addd after `zig build run --` to the executable.
    if (b.args) |args| {
        run.addArgs(args);
    }

    // Setup zig build tests cmd that runs all tests in the root_module.
    const tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);

    // Setup zls for build on save.
    const exe_check = b.addExecutable(.{
        .name = "check",
        .root_module = mod,
    });
    const check_step = b.step("check", "Check if raytracer compiles");
    check_step.dependOn(&exe_check.step);
    check_step.dependOn(&tests.step);

    inline for (libs) |lib| {
        addLib(b, mod, test_step, check_step, lib.name, lib.path);
    }
}

const libs = &.{
    .{ .name = "xml", .path = "lib/xml.zig" },
    .{ .name = "ppm", .path = "lib/ppm.zig" },
};

fn addLib(
    b: *std.Build,
    mod: *std.Build.Module,
    test_step: *std.Build.Step,
    check_step: *std.Build.Step,
    lib_name: []const u8,
    lib_path: []const u8,
) void {
    const lib = b.addModule(lib_name, .{
        .root_source_file = b.path(lib_path),
        .target = mod.resolved_target.?,
        .optimize = mod.optimize.?,
    });
    const tests = b.addTest(.{ .root_module = lib });
    mod.addImport(lib_name, lib);
    test_step.dependOn(&b.addRunArtifact(tests).step);
    check_step.dependOn(&tests.step);
}
