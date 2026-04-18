const std = @import("std");
const raytracer = @import("raytracer.zig");

// TODO: Implement utilities for cmdline arg parsing.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena;
    const allocator = arena.allocator();
    const io = init.io;

    const scene_file = try std.Io.Dir.cwd().openFile(io, "scene.xml", .{});
    defer scene_file.close(io);

    const scene = try raytracer.Scene.fromXmlFile(allocator, io, scene_file);
    try scene.intoImgFile(allocator, io, std.Io.Dir.cwd());
}

test {
    std.testing.refAllDecls(@This());
}
