const std = @import("std");
const vec = @import("vec");

const Look = @This();

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

pub const Raw = struct {
    from: [3]f32 = .{ 0, 0, -7 },
    at: [3]f32 = .{ 0, 0, 0 },
    up: [3]f32 = .{ 0, 1, 0 },

    pub fn intoInternal(self: @This()) Look {
        return .{
            .from = self.from,
            .at = self.at,
            .up = self.up,
        };
    }
};
