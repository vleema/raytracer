const vec = @import("vec");

const Color = @import("Color.zig");
const Light = @import("Light.zig");

const Material = @This();

tag: Tag,
name: []const u8 = "default",
extra_idx: u32 = 0,

pub const Tag = enum {
    flat,
    blinn,
};

pub const Flat = struct {
    color: Color = .{},

    pub const Raw = struct {
        color: Color.Raw = .{ .hex = "#ff0000" },
    };

    pub fn fromRaw(r: Flat.Raw) !Flat {
        return .{ .color = try .fromRaw(r.color) };
    }
};

pub const Blinn = struct {
    ambient: [3]f32,
    diffuse: [3]f32,
    specular: [3]f32,
    mirror: [3]f32,
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
            .mirror = self.mirror,
            .glossiness = self.glossiness,
        };
    }
};

pub const Raw = struct {
    name: []const u8,
    inner: union(Tag) {
        flat: Flat.Raw,
        blinn: Blinn,
    },

    pub fn intoInternal(self: @This()) !Material {
        return .{
            .tag = self.inner,
            .name = self.name,
        };
    }
};
