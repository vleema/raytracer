const std = @import("std");
const xml = @import("xml");
const vec = @import("vec");
const Real = vec.Real;

pub const Pixel = struct {
    pos: UnsignedPoint(2),
    color: Color,
};

pub const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,

    // TODO: Possibly add support for hexadecimal values.
    pub fn fromStr(str: ?[]const u8) !@This() {
        if (str == null or str.?.len == 0) return .{};
        const arr = try xml.parseUnsignedArray(u8, 3, str.?);
        return .{ .r = arr[0], .g = arr[1], .b = arr[2] };
    }

    fn interpolate(x: u8, y: u8, f: f64) u8 {
        if (f > 1 or f < 0) std.debug.panic(
            "lerp: the blend factor in lerp cannot be outside [0,1] range, found {any}",
            .{f},
        );
        return @as(u8, @intFromFloat((1.0 - f) * @as(f64, @floatFromInt(x)) + f * @as(f64, @floatFromInt(y))));
    }

    fn lerp(self: @This(), other: @This(), f: f64) @This() {
        return @This(){
            .r = interpolate(self.r, other.r, f),
            .g = interpolate(self.g, other.g, f),
            .b = interpolate(self.b, other.b, f),
        };
    }
};

/// Executes a bilinear interpolation of pixels.
pub fn bilerp(
    tl: Pixel,
    tr: Pixel,
    bl: Pixel,
    br: Pixel,
    pos: Real(2),
) Color {
    const horizontal_factor = factor(@floatFromInt(tl.pos[0]), @floatFromInt(tr.pos[0]), pos[0]);
    const vertical_factor = factor(@floatFromInt(tl.pos[1]), @floatFromInt(bl.pos[1]), pos[1]);
    const top = tl.color.lerp(tr.color, horizontal_factor);
    const bot = bl.color.lerp(br.color, horizontal_factor);
    return top.lerp(bot, vertical_factor);
}

fn factor(x1: f64, x2: f64, x: f64) f64 {
    return std.math.clamp((x - x1) / (x2 - x1), 0, 1);
}

/// Represents a element of a vector space of unsigned points.
pub fn UnsignedPoint(N: comptime_int) type {
    return @Vector(N, u32);
}
