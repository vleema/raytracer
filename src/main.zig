const std = @import("std");
const img = @import("img.zig");

// TODO: Implement utilities for cmdline arg parsing.
pub fn main() !void {
    var out = try std.fs.cwd().createFile("out.ppm", .{});
    defer out.close();

    const scene_file = try std.fs.cwd().openFile("scene.xml", .{});
    const scene = try img.Scene.fromFile(scene_file);

    var buf: [1 << 16]u8 = undefined;
    var fwriter = out.writer(&buf);
    const writer = &fwriter.interface;

    // TODO: Implement modules for writing to a ppm and png file.
    try writer.print("P6\n", .{});
    try writer.print("{d} {d}\n", .{ scene.film.x_res, scene.film.y_res });
    try writer.print("255\n", .{});

    for (0..scene.film.y_res) |y| {
        for (0..scene.film.x_res) |x| {
            const color = scene.backgroundPixel(.{ x, y });
            try writer.writeAll(&.{ color.r, color.g, color.b });
        }
    }

    try writer.flush();
}
