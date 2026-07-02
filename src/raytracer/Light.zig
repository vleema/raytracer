const vec = @import("vec");

const Material = @import("Material.zig");

const Light = @This();

tag: Tag,
common: Common,

pub const Tag = enum {
    ambient,
    directional,
    point,
    spotlight,
};

pub const Common = struct {
    intensity: [3]f32,
    attenuation: Attenuation,
    extra_idx: u32 = 0,

    pub const Attenuation = struct {
        constant: f32,
        linear: f32,
        quadratic: f32,

        pub fn val(self: *const @This(), dist: f32) f32 {
            return 1.0 / (self.constant + self.linear *
                dist + self.quadratic * dist * dist);
        }
    };

    pub fn attenuate(
        self: *const @This(),
        material: *const Material.Blinn,
        dist: f32,
    ) Material.Blinn {
        const val = self.attenuation.val(dist);
        return .{
            .ambient = vec.mul_scalar(3, f32, val, material.ambient),
            .diffuse = vec.mul_scalar(3, f32, val, material.diffuse),
            .specular = vec.mul_scalar(3, f32, val, material.specular),
            .glossiness = material.glossiness,
        };
    }
};

pub const Ambient = struct {};

pub const Directional = struct {
    from: [3]f32,
    to: [3]f32,
};

pub const Point = struct {
    from: [3]f32,
};

pub const Spotlight = struct {
    from: [3]f32,
    to: [3]f32,
    cutoff: f32 = 60,
    falloff: f32 = 30,
};

pub const Variant = union(Tag) {
    ambient: Ambient,
    directional: Directional,
    point: Point,
    spotlight: Spotlight,
};

pub const Raw = struct {
    inner: Variant,
    scale: [3]f32 = .{ 1, 1, 1 },
    intensity: [3]f32 = .{ 1, 1, 1 },
    attenuation: Common.Attenuation = .{
        .constant = 1,
        .linear = 0.09,
        .quadratic = 0.032,
    },

    pub fn intoInternal(self: @This()) !Light {
        return .{
            .tag = self.inner,
            .common = .{
                .intensity = vec.mul(3, f32, .{ self.intensity, self.scale }),
                .attenuation = self.attenuation,
            },
        };
    }
};
