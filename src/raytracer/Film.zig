const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const png = @import("png");
const ppm = @import("ppm");

const Color = @import("Color.zig");

const Film = @This();

tag: enum { image } = .image,
width: u32 = 400,
height: u32 = 200,
filename: []const u8 = "out.png",
format: enum { ppm, png } = .png,
buf: []const Color = &.{},

pub fn intoImg(
    self: *Film,
    gpa: Allocator,
    io: Io,
    dir: Io.Dir,
    buf: []const Color,
) !void {
    self.buf = buf;

    var out = try dir.createFile(io, self.filename, .{});
    defer out.close(io);

    switch (self.format) {
        .png => try png.writeTrueColor8(self, gpa, io, out, self.width, self.height),
        .ppm => try ppm.writeP6(self, io, out, self.width, self.height),
    }
}

pub fn color(self: *const Film, x: u32, y: u32) [3]u8 {
    const c = self.buf[x + y * self.width];
    return [_]u8{ c.r, c.g, c.b };
}
