const std = @import("std");
const ppm = @import("ppm");
const png = @import("png");
const img = @import("img.zig");

// TODO: Implement png library.
// TODO: Implement utilities for cmdline arg parsing.
pub fn main() !void {
    const scene_file = try std.fs.cwd().openFile("scene.xml", .{});
    defer scene_file.close();
    const scene = try img.Scene.fromFile(scene_file);
    try scene.intoImg(std.heap.smp_allocator, std.fs.cwd());
}

test {
    std.testing.refAllDecls(@This());
}
