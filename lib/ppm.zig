const std = @import("std");

/// Writes to PPM P6 file using the method `render` from a `renderer` to define a color of a position.
///
/// The `renderer` should have a method `render(self, x: u32, y: u32) [3]u8`.
/// The `render` function will be used to compute the color of each iterated pixel.
pub fn writeP6(
    renderer: anytype,
    io: std.Io,
    file: std.Io.File,
    width: u32,
    height: u32,
) !void {
    var buf: [1 << 16]u8 = undefined;
    var fw = file.writer(io, &buf);
    const w = &fw.interface;

    try w.print("P6\n", .{});
    try w.print("{d} {d}\n", .{ width, height });
    try w.print("255\n", .{});

    for (0..height) |y| {
        for (0..width) |x| {
            const color: [3]u8 = renderer.render(@intCast(x), @intCast(y));
            try w.writeAll(&color);
        }
    }

    try w.flush();
}
