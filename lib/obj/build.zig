const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_opts = .{
        "TOBJ_ENABLE_FILE_IO",
        "TOBJ_ENABLE_MULTITHREADING",
        "TOBJ_ENABLE_SIMD",
    };
    const tinyobj = b.addTranslateC(.{
        .root_source_file = b.path("c/c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const tinyobj_mod = tinyobj.addModule("obj");
    inline for (c_opts) |o| tinyobj_mod.addCMacro(o, "");
    tinyobj_mod.addCSourceFiles(.{ .files = &.{ "c/tiny_obj_c.c", "c/tobj_tess.c" } });
}
