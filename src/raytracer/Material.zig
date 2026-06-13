const std = @import("std");
const eql = std.mem.eql;

const Color = @import("Color.zig");

const Material = @This();

tag: Tag = .flat,
common: Common = .{},

const log = std.log.scoped(.material);

pub const Tag = enum {
    flat,
    blinn,
};

pub const Common = struct {
    color: Color = .{},
    extra_idx: u32 = 0,
};

pub const Flat = struct {};

pub const Blinn = struct {
    ambient: [3]f32,
    diffuse: [3]f32,
    specular: [3]f32,
    glossiness: f32,
};

pub const Raw = struct {
    name: []const u8,
    inner: union(Tag) {
        flat: struct {},
        blinn: Blinn,
    },
    color: Color.Raw,

    pub fn intoInternal(self: @This()) !Material {
        return .{
            .tag = self.inner,
            .common = .{ .color = try self.color.intoInternal() },
        };
    }
};
