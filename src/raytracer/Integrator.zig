const std = @import("std");
const math = std.math;

const vec = @import("vec");
const Real = vec.Real;

const Camera = @import("Camera.zig").Camera;
const Color = @import("Color.zig");
const Frame = @import("Look.zig").Frame;
const Material = @import("Material.zig");
const Object = @import("Object.zig");
const Ray = @import("Ray.zig");
const World = @import("World.zig");

pub const Integrator = union(enum) {
    flat: Flat,
    blinn: Blinn,

    pub fn render(
        self: *const Integrator,
        buf: []Color,
        world: *const World,
        camera: *const Camera,
        frame: *const Frame,
        width: u32,
        height: u32,
    ) void {
        camera.preprocess(width, height);

        for (0..height) |y| {
            for (0..width) |x| {
                const ray = camera.generateRay(@intCast(x), @intCast(y), width, height, frame);
                const color = if (world.objHit(&ray)) |v|
                    self.li(world, ray, v.hit, v.material)
                else
                    world.background.ptColor(
                        width,
                        height,
                        .{ @floatFromInt(x), @floatFromInt(y) },
                    );

                buf[x + y * width] = color;
            }
        }
    }

    fn li(
        self: *const Integrator,
        world: *const World,
        ray: Ray,
        hit: Object.Hit,
        material: Material,
    ) Color {
        return switch (self.*) {
            .blinn => Blinn.li(world, ray, hit, material),
            .flat => Flat.li(world, ray, hit, material),
        };
    }
};

pub const Flat = struct {
    pub fn li(
        _: *const World,
        _: Ray,
        _: Object.Hit,
        material: Material,
    ) Color {
        return material.common.color;
    }
};

pub const Blinn = struct {
    pub fn li(
        world: *const World,
        ray: Ray,
        hit: Object.Hit,
        material: Material,
    ) Color {
        if (material.tag != .blinn) return material.common.color;
        const blinn = world.materials.blinn.items[material.common.extra_idx];

        const normal: Real(3) = hit.normal;
        const view: Real(3) = -@as(Real(3), ray.direction);
        const hit_pt = ray.at(hit.t);

        var ambient: Real(3) = .{ 0, 0, 0 };
        var lights: Real(3) = .{ 0, 0, 0 };

        const slice = world.lights.list.slice();
        for (slice.items(.tag), slice.items(.common)) |tag, common| {
            switch (tag) {
                .ambient => {
                    ambient += @as(Real(3), blinn.ambient) *
                        @as(Real(3), common.scale) *
                        @as(Real(3), common.intensity);
                },
                .directional, .point => {
                    const light = switch (tag) {
                        .directional => blk: {
                            const directional = world.lights.directional.items[common.extra_idx];
                            break :blk vec.normalize(3, f32, vec.sub(3, f32, directional.from, directional.to));
                        },
                        .point => blk: {
                            const point = world.lights.point.items[common.extra_idx];
                            break :blk vec.normalize(3, f32, vec.sub(3, f32, point.from, hit_pt));
                        },
                        else => unreachable,
                    };

                    const half_vector = vec.normalize(3, f32, view + light);
                    const n_dot_h = vec.dot(3, f32, normal, half_vector);
                    const n_dot_l = vec.dot(3, f32, normal, light);
                    const intensity = vec.mul(3, f32, common.intensity, common.scale);

                    lights += intensity * vec.mul_scalar(3, f32, @max(0, n_dot_l), blinn.diffuse);
                    lights += intensity * vec.mul_scalar(3, f32, math.pow(f32, @max(0, n_dot_h), blinn.glossiness), blinn.specular);
                },
            }
        }

        const total = ambient + lights;
        const base = Color.toReal(material.common.color);

        return .fromReal(base * total);
    }
};
