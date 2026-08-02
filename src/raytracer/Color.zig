const std = @import("std");
const math = std.math;

const vec = @import("vec");
const Real = vec.Real;

// TODO: Consider changing this to float.

r: u8 = 1,
g: u8 = 1,
b: u8 = 1,

const Color = @This();

pub const Raw = union(enum) {
    hex: []const u8,
    rgb_u8: [3]u8,
    rgb_f32: [3]f32,
};

pub const Pixel = struct {
    position: [2]u32,
    color: Color,

    /// Executes a bilinear interpolation of pixels.
    pub fn interpolate(
        top_left: Pixel,
        top_right: Pixel,
        bottom_left: Pixel,
        bottom_right: Pixel,
        position: [2]f32,
    ) Color {
        const factor_horizontal = factor(
            @floatFromInt(top_left.position[0]),
            @floatFromInt(top_right.position[0]),
            position[0],
        );
        const factor_vertical = factor(
            @floatFromInt(top_left.position[1]),
            @floatFromInt(bottom_left.position[1]),
            position[1],
        );
        const top = top_left.color.interpolate(
            top_right.color,
            factor_horizontal,
        );
        const bottom = bottom_left.color.interpolate(
            bottom_right.color,
            factor_horizontal,
        );
        return top.interpolate(bottom, factor_vertical);
    }

    fn factor(x1: f32, x2: f32, x: f32) f32 {
        return std.math.clamp((x - x1) / (x2 - x1), 0, 1);
    }
};

pub fn fromRaw(raw: Raw) !Color {
    return switch (raw) {
        .hex => |s| try Color.fromHex(s),
        .rgb_u8 => |a| .{ .r = a[0], .g = a[1], .b = a[2] },
        .rgb_f32 => |a| .{
            .r = @intFromFloat(@min(a[0] * 255, 255)),
            .g = @intFromFloat(@min(a[1] * 255, 255)),
            .b = @intFromFloat(@min(a[2] * 255, 255)),
        },
    };
}

pub fn fromHex(string: ?[]const u8) !Color {
    if (string == null or string.?.len == 0) return .{};

    const array = if (string.?.len == 7 and string.?[0] == '#')
        .{
            try std.fmt.parseUnsigned(u8, string.?[1..3], 16),
            try std.fmt.parseUnsigned(u8, string.?[3..5], 16),
            try std.fmt.parseUnsigned(u8, string.?[5..7], 16),
        }
    else
        return error.InvalidHex;

    return .{ .r = array[0], .g = array[1], .b = array[2] };
}

pub fn fromReal(raw: Real(3)) Color {
    return .{
        .r = @intFromFloat(math.clamp(raw[0], 0.0, 1.0) * 255),
        .g = @intFromFloat(math.clamp(raw[1], 0.0, 1.0) * 255),
        .b = @intFromFloat(math.clamp(raw[2], 0.0, 1.0) * 255),
    };
}

pub fn toReal(self: Color) Real(3) {
    var real: Real(3) = .{
        @floatFromInt(self.r),
        @floatFromInt(self.g),
        @floatFromInt(self.b),
    };
    real /= @splat(255);
    return real;
}

pub fn interpolate(self: Color, other: Color, factor: f32) Color {
    return @This(){
        .r = interpolateChannel(self.r, other.r, factor),
        .g = interpolateChannel(self.g, other.g, factor),
        .b = interpolateChannel(self.b, other.b, factor),
    };
}

fn interpolateChannel(x: u8, y: u8, factor: f32) u8 {
    if (factor > 1 or factor < 0) std.debug.panic(
        "lerp: the blend factor in lerp cannot be outside [0,1] range, found {any}",
        .{factor},
    );
    return @as(u8, @intFromFloat((1.0 - factor) * @as(f32, @floatFromInt(x)) +
        factor * @as(f32, @floatFromInt(y))));
}

test "Color: from hex str" {
    const str = "#ffa0bc";
    const actual = try Color.fromHex(str);
    const expected = Color{ .r = 255, .g = 160, .b = 188 };
    try std.testing.expectEqual(expected, actual);
}
