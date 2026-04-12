const std = @import("std");
const raytracer = @import("raytracer.zig");

// TODO: Implement utilities for cmdline arg parsing.
pub fn main() !void {
    const scene_file = try std.fs.cwd().openFile("scene.xml", .{});
    defer scene_file.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const scene = try raytracer.Scene.fromXmlFile(allocator, scene_file);
    try scene.intoImgFile(allocator, std.fs.cwd());
}

test {
    std.testing.refAllDecls(@This());
}
