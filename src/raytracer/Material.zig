const vec = @import("vec");

const Color = @import("Color.zig");
const Light = @import("Light.zig");

const Material = @This();

tag: Tag = .flat,
common: Common = .{},

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

    pub fn attenuate(
        self: *const Blinn,
        attenuation: Light.Common.Attenuation,
        dist: f32,
    ) @This() {
        const val = attenuation.val(dist);
        return .{
            .ambient = vec.mul_scalar(3, f32, val, self.ambient),
            .diffuse = vec.mul_scalar(3, f32, val, self.diffuse),
            .specular = vec.mul_scalar(3, f32, val, self.specular),
            .glossiness = self.glossiness,
        };
    }
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
