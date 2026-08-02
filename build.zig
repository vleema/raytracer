const std = @import("std");
const builtin = @import("builtin");
const OptimizeMode = std.builtin.OptimizeMode;

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.addModule("raytracer", .{
        .root_source_file = b.path("src/raytracer/raytracer.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "raytracer",
        .root_module = b.addModule("raytracer-exe", .{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "raytracer", .module = root_module },
            },
        }),
    });

    b.installArtifact(exe);

    // Setup zig build run that runs the main module executable.
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run.step);

    // Pass args after `zig build run --` to the executable.
    if (b.args) |args| {
        run.addArgs(args);
    }

    // Setup zig build tests cmd that runs all tests in the root_module.
    const tests = b.addTest(.{ .root_module = root_module });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);

    // Setup lint step.
    const zlint = b.dependency("zlint", .{
        .target = target,
        .optimize = OptimizeMode.ReleaseSafe,
    });
    const zlint_exe = zlint.artifact("zlint");
    const zlint_run = b.addRunArtifact(zlint_exe);

    // Pass args after `zig build lint --` to the executable.
    if (b.args) |args| {
        zlint_run.addArgs(args);
    }

    const lint_step = b.step("lint", "Lint the project with zlint");
    lint_step.dependOn(&zlint_run.step);

    // Setup zls for build on save.
    const exe_check = b.addExecutable(.{
        .name = "check",
        .root_module = root_module,
    });
    const check_step = b.step("check", "Checks if raytracer compiles");
    check_step.dependOn(&exe_check.step);
    check_step.dependOn(&tests.step);

    var libraries = [_]Library{
        .{ .name = "obj", .path = "src/lib/obj.zig", .imports = &.{"vec"} },
        .{ .name = "png", .path = "src/lib/png.zig" },
        .{ .name = "ppm", .path = "src/lib/ppm.zig" },
        .{ .name = "pre", .path = "src/lib/pre.zig" },
        .{ .name = "vec", .path = "src/lib/vec.zig" },
    };
    createModulesAndTests(libraries.len, &libraries, b, target, optimize);
    resolveImports(libraries.len, &libraries, b);
    addLibraries(libraries.len, libraries, b, root_module, test_step, check_step);

    // Autodoc treats the directory containing a module root as that module's source tree. So we
    // should create a directory for every flat library file so siblings under each other's
    // namespaces.
    //
    // This shouldn't be necessary but is the best we have over creating a directory for every
    // single library file.
    const docs_sources = b.addWriteFiles();
    createDocsModules(libraries.len, &libraries, b, docs_sources, target, optimize);
    resolveDocsImports(libraries.len, &libraries);

    const raytracer_docs_module = b.createModule(.{
        .root_source_file = b.path("src/raytracer/raytracer.zig"),
        .target = target,
        .optimize = optimize,
    });
    for (libraries) |library|
        raytracer_docs_module.addImport(library.name, library.docs_module.?);

    const docs_module = b.createModule(.{
        .root_source_file = docs_sources.addCopyFile(
            b.path("src/docs.zig"),
            "docs/docs.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    docs_module.addImport("raytracer", raytracer_docs_module);
    for (libraries) |library|
        docs_module.addImport(library.name, library.docs_module.?);

    const docs_artifact = b.addObject(.{
        .name = "docs",
        .root_module = docs_module,
    });
    const docs = b.addInstallDirectory(.{
        .source_dir = docs_artifact.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);
}

const Library = struct {
    name: []const u8,
    path: []const u8,
    imports: []const []const u8 = &.{},
    module: ?*std.Build.Module = null,
    docs_module: ?*std.Build.Module = null,
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
            .root_source_file = libraryRootPath(b, library.*),
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

fn createDocsModules(
    n: comptime_int,
    libraries: *[n]Library,
    b: *std.Build,
    docs_sources: *std.Build.Step.WriteFile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    for (libraries) |*library| {
        const root_source_file = if (std.mem.endsWith(u8, library.path, ".zig"))
            docs_sources.addCopyFile(
                b.path(library.path),
                b.fmt("{s}/{s}.zig", .{ library.name, library.name }),
            )
        else
            libraryRootPath(b, library.*);

        library.docs_module = b.createModule(.{
            .root_source_file = root_source_file,
            .target = target,
            .optimize = optimize,
        });
    }
}

fn libraryRootPath(b: *std.Build, library: Library) std.Build.LazyPath {
    if (std.mem.endsWith(u8, library.path, ".zig")) return b.path(library.path);
    return b.path(b.fmt("{s}/{s}.zig", .{
        library.path,
        std.fs.path.basename(library.path),
    }));
}

fn resolveDocsImports(n: comptime_int, libraries: *[n]Library) void {
    for (libraries) |*library| for (library.imports) |import_name| {
        for (libraries) |dependency| {
            if (std.mem.eql(u8, dependency.name, import_name)) {
                library.docs_module.?.addImport(import_name, dependency.docs_module.?);
                break;
            }
        } else @panic("unknown library import");
    };
}

fn addLibraries(
    n: comptime_int,
    libraries: [n]Library,
    b: *std.Build,
    root_module: *std.Build.Module,
    test_step: *std.Build.Step,
    check_step: *std.Build.Step,
) void {
    for (libraries) |library| {
        root_module.addImport(library.name, library.module.?);
        test_step.dependOn(&b.addRunArtifact(library.tests.?).step);
        check_step.dependOn(&library.tests.?.step);
    }
}
