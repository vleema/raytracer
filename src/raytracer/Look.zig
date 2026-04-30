const std = @import("std");
const vec = @import("vec");
const xml = @import("xml");

from: @Vector(3, f32) = .{ 0, 0, -7 },
at: @Vector(3, f32) = .{ 0, 0, 0 },
up: @Vector(3, f32) = .{ 0, 1, 0 },

pub const Frame = struct {
    origin: @Vector(3, f32),
    right: @Vector(3, f32),
    orientation: @Vector(3, f32),
    direction: @Vector(3, f32),
};

pub fn normalFrame(self: @This()) Frame {
    const gaze = self.at - self.from;
    const direction = vec.normalize(3, f32, gaze);
    const right = vec.normalize(3, f32, vec.cross3(f32, self.up, direction));
    const orientation = vec.normalize(3, f32, vec.cross3(f32, direction, right));
    return Frame{
        .origin = self.from,
        .right = right,
        .orientation = orientation,
        .direction = direction,
    };
}

pub fn fromXml(elem: *const xml.Element) !@This() {
    var ret = @This(){};
    const cb = struct {
        fn call(val: []const u8) anyerror!f32 {
            const i = try std.fmt.parseInt(i32, val, 10);
            return @floatFromInt(i);
        }
    }.call;

    if (elem.queryAttribute("look_from", null)) |v| {
        ret.from = try xml.parseArray(f32, 3, cb, v);
    }
    if (elem.queryAttribute("look_at", null)) |v| {
        ret.at = try xml.parseArray(f32, 3, cb, v);
    }
    if (elem.queryAttribute("up", null)) |v| {
        ret.up = try xml.parseArray(f32, 3, cb, v);
    }

    return ret;
}
