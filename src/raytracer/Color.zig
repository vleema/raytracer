const std = @import("std");
const math = std.math;

const vec = @import("vec");
const Real = vec.Real;

const Color = @This();

r: u8 = 0,
g: u8 = 0,
b: u8 = 0,

pub const Raw = union(enum) {
    hex: []const u8,
    rgb_u8: [3]u8,
    rgb_f32: [3]f32,

    pub fn intoInternal(self: @This()) !Color {
        return switch (self) {
            .hex => |s| try Color.fromHex(s),
            .rgb_u8 => |a| .{ .r = a[0], .g = a[1], .b = a[2] },
            .rgb_f32 => |a| .{
                .r = @intFromFloat(@min(a[0] * 255, 255)),
                .g = @intFromFloat(@min(a[1] * 255, 255)),
                .b = @intFromFloat(@min(a[2] * 255, 255)),
            },
        };
    }
};

pub fn fromHex(str: ?[]const u8) !@This() {
    if (str == null or str.?.len == 0) return .{};

    const array = if (str.?.len == 7 and str.?[0] == '#')
        .{
            try std.fmt.parseUnsigned(u8, str.?[1..3], 16),
            try std.fmt.parseUnsigned(u8, str.?[3..5], 16),
            try std.fmt.parseUnsigned(u8, str.?[5..7], 16),
        }
    else
        return error.InvalidHex;

    return .{ .r = array[0], .g = array[1], .b = array[2] };
}

pub fn fromReal(r: Real(3)) Color {
    return .{
        .r = @intFromFloat(math.clamp(r[0], 0.0, 1.0) * 255),
        .g = @intFromFloat(math.clamp(r[1], 0.0, 1.0) * 255),
        .b = @intFromFloat(math.clamp(r[2], 0.0, 1.0) * 255),
    };
}

pub fn toReal(c: Color) Real(3) {
    var ret: Real(3) = .{
        @floatFromInt(c.r),
        @floatFromInt(c.g),
        @floatFromInt(c.b),
    };
    ret /= @splat(255);
    return ret;
}

pub fn lerp(self: @This(), other: @This(), f: f32) @This() {
    return @This(){
        .r = interpolate(self.r, other.r, f),
        .g = interpolate(self.g, other.g, f),
        .b = interpolate(self.b, other.b, f),
    };
}

fn interpolate(x: u8, y: u8, f: f32) u8 {
    if (f > 1 or f < 0) std.debug.panic(
        "lerp: the blend factor in lerp cannot be outside [0,1] range, found {any}",
        .{f},
    );
    return @as(u8, @intFromFloat((1.0 - f) * @as(f32, @floatFromInt(x)) + f * @as(f32, @floatFromInt(y))));
}

test "Color: from hex str" {
    const str = "#ffa0bc";
    const actual = try Color.fromHex(str);
    const expected = Color{ .r = 255, .g = 160, .b = 188 };
    try std.testing.expectEqual(expected, actual);
}
