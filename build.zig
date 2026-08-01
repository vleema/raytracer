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

    const docs_mod = b.addModule("docs", .{
        .root_source_file = b.path("src/docs.zig"),
        .target = target,
        .optimize = optimize,
    });
    const docs_artifact = b.addObject(.{
        .name = "docs",
        .root_module = docs_mod,
    });
    const docs = b.addInstallDirectory(.{
        .source_dir = docs_artifact.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);

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

    var libraries = [_]Library{
        .{ .name = "obj", .path = "lib/obj.zig", .imports = &.{"vec"} },
        .{ .name = "png", .path = "lib/png.zig" },
        .{ .name = "ppm", .path = "lib/ppm.zig" },
        .{ .name = "pre", .path = "lib/pre.zig" },
        .{ .name = "vec", .path = "lib/vec.zig" },
    };
    createModulesAndTests(libraries.len, &libraries, b, target, optimize);
    resolveImports(libraries.len, &libraries, b);
    addLibraries(libraries.len, libraries, b, mod, docs_mod, test_step, check_step);
}

const Library = struct {
    name: []const u8,
    path: []const u8,
    imports: []const []const u8 = &.{},
    module: ?*std.Build.Module = null,
    tests: ?*std.Build.Step.Compile = null,
};

fn createModulesAndTests(
    n: comptime_int,
    libraries: *[n]Library,
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    for (libraries) |*library| {
        library.module = b.addModule(library.name, .{
            .root_source_file = b.path(library.path),
            .optimize = optimize,
            .target = target,
        });
        library.tests = b.addTest(
            .{ .root_module = library.module.? },
        );
    }
}

fn resolveImports(n: comptime_int, libraries: *[n]Library, b: *std.Build) void {
    for (libraries) |*library| for (library.imports) |import|
        library.module.?.addImport(import, b.modules.get(import).?);
}

fn addLibraries(
    n: comptime_int,
    libraries: [n]Library,
    b: *std.Build,
    main_module: *std.Build.Module,
    docs_module: *std.Build.Module,
    test_step: *std.Build.Step,
    check_step: *std.Build.Step,
) void {
    for (libraries) |library| {
        main_module.addImport(library.name, library.module.?);
        docs_module.addImport(library.name, library.module.?);
        test_step.dependOn(&b.addRunArtifact(library.tests.?).step);
        check_step.dependOn(&library.tests.?.step);
    }
}
