const std = @import("std");

pub fn Point(N: comptime_int) type {
    return @Vector(N, usize);
}

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    fn interpolate(x: u8, y: u8, f: f64) u8 {
        if (f > 1 or f < 0) std.debug.panic(
            "lerp: the blend factor in lerp cannot be outside [0,1] range, found {any}",
            .{f},
        );
        return @as(u8, @intFromFloat((1.0 - f) * @as(f64, @floatFromInt(x)) + f * @as(f64, @floatFromInt(y))));
    }

    pub fn lerp(self: @This(), other: @This(), f: f64) @This() {
        return @This(){
            .r = interpolate(self.r, other.r, f),
            .g = interpolate(self.g, other.g, f),
            .b = interpolate(self.b, other.b, f),
        };
    }
};

pub const Pixel = struct {
    pos: Point(2),
    color: Color,
};

fn factor(x1: f64, x2: f64, x: f64) f64 {
    return (x - x1) / (x2 - x1);
}

pub fn bilerp(tl: Pixel, tr: Pixel, bl: Pixel, br: Pixel, pos: Point(2)) Color {
    const horizontal_factor = factor(@floatFromInt(tl.pos[0]), @floatFromInt(tr.pos[0]), @floatFromInt(pos[0]));
    const vertical_factor = factor(@floatFromInt(tl.pos[1]), @floatFromInt(bl.pos[1]), @floatFromInt(pos[1]));
    const top = tl.color.lerp(tr.color, horizontal_factor);
    const bot = bl.color.lerp(br.color, horizontal_factor);
    return top.lerp(bot, vertical_factor);
}


pub fn main() !void {
    var f = try std.fs.cwd().createFile("out.ppm", .{});
    defer f.close();

    var buf: [1 << 16]u8 = undefined;
    var fwriter = f.writer(&buf);
    const writer = &fwriter.interface;

    const width = 16 * 60;
    const height = 9 * 60;

    const tl = Pixel{ .pos = .{ 0, 0 }, .color = Color{ .r = 0x0, .g = 0xff, .b = 0x0 } };
    const tr = Pixel{ .pos = .{ width, 0 }, .color = Color{ .r = 0xff, .g = 0xff, .b = 0x0 } };
    const bl = Pixel{ .pos = .{ 0, height }, .color = Color{ .r = 0x0, .g = 0x0, .b = 0xff } };
    const br = Pixel{ .pos = .{ width, height }, .color = Color{ .r = 0xff, .g = 0x0, .b = 0x0 } };

    try writer.print("P6\n", .{});
    try writer.print("{d} {d}\n", .{ width, height });
    try writer.print("255\n", .{});

    for (0..height) |y| {
        for (0..width) |x| {
            const color = bilerp(tl, tr, bl, br, .{ x, y });
            try writer.writeAll(&.{ color.r, color.g, color.b });
        }
    }

    try writer.flush();
}
