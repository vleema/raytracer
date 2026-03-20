const std = @import("std");
const ppm = @import("ppm");
const img = @import("img.zig");

// TODO: Implement png library.
// TODO: Implement utilities for cmdline arg parsing.
pub fn main() !void {
    const scene_file = try std.fs.cwd().openFile("scene.xml", .{});
    defer scene_file.close();
    const scene = try img.Scene.fromFile(scene_file);

    var out = try std.fs.cwd().createFile("out.ppm", .{});
    defer out.close();

    try ppm.writeP6(&out, scene.film.x_res, scene.film.y_res, scene);
}
