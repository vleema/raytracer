const std = @import("std");
const math = std.math;

const vec = @import("vec");
const Real = vec.Real;

const Camera = @import("Camera.zig").Camera;
const Color = @import("Color.zig");
const Frame = @import("Look.zig").Frame;
const Light = @import("Light.zig");
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
                const color = if (world.objHit(&ray, 0, std.math.inf(f32))) |v|
                    self.li(world, ray, v.hit, v.material, 0)
                else
                    // TODO: Add texture background.
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
        depth: u32,
    ) Color {
        return switch (self.*) {
            inline else => |v| v.li(world, ray, hit, material, depth),
        };
    }
};

pub const Flat = struct {
    pub fn li(
        _: anytype,
        _: anytype,
        _: anytype,
        _: anytype,
        material: Material,
        _: anytype,
    ) Color {
        return material.common.color;
    }
};

pub const Blinn = struct {
    max_depth: u32 = 3,

    pub fn li(
        self: *const Blinn,
        world: *const World,
        ray: Ray,
        hit: Object.Hit,
        material: Material,
        depth: u32,
    ) Color {
        if (material.tag != .blinn) return material.common.color;
        const blinn = world.materials.blinn.items[material.common.extra_idx];

        const view: Real(3) = -@as(Real(3), ray.direction);
        const hit_pt = ray.at(hit.t);
        const dist = vec.len(3, f32, vec.sub(3, f32, hit_pt, ray.origin));

        var light_contrib: Real(3) = .{ 0, 0, 0 };
        const slice = world.lights.list.slice();
        for (slice.items(.tag), slice.items(.common)) |tag, common| {
            const light: Light = .{ .common = common, .tag = tag };
            light_contrib += lightContrib(world, light, view, hit.normal, hit_pt, dist, blinn);
        }
        if (depth < self.max_depth) {
            const direction = view -
                vec.mul_scalar(3, f32, vec.dot(3, f32, view, hit.normal), hit.normal);
            const reflected: Ray = .{ .direction = direction, .origin = hit_pt };
            if (world.objHit(&reflected, 0.0001, math.inf(f32))) |h| {
                light_contrib += blinn.mirror * self.li(world, reflected, h.hit, h.material, depth + 1).toReal();
            }
        }
        const base = material.common.color.toReal();
        return .fromReal(base * light_contrib);
    }

    fn lightContrib(
        world: *const World,
        light: Light,
        view: Real(3),
        normal: Real(3),
        hit_pt: [3]f32,
        dist: f32,
        material: Material.Blinn,
    ) Real(3) {
        const light_dir, const intensity, const attenuated, const shadow_max =
            switch (light.tag) {
                .ambient => return vec.mul(3, f32, .{
                    material.ambient,
                    light.common.intensity,
                }),
                // TODO: Use shadow ray as bounding box of objects.
                .directional => blk: {
                    const payload = world.lights.directional.items[light.common.extra_idx];
                    const light_dir = vec.normalize(3, f32, vec.sub(3, f32, payload.from, payload.to));
                    break :blk .{ light_dir, light.common.intensity, material, 50 };
                },
                .point => blk: {
                    const payload = world.lights.point.items[light.common.extra_idx];
                    const light_dir = vec.normalize(3, f32, vec.sub(3, f32, payload.from, hit_pt));
                    break :blk .{
                        light_dir,
                        light.common.intensity,
                        light.common.attenuate(&material, dist),
                        std.math.inf(f32),
                    };
                },
                .spotlight => blk: {
                    const payload = world.lights.spotlight.items[light.common.extra_idx];
                    const opposite = vec.normalize(3, f32, vec.sub(3, f32, payload.from, payload.to));
                    const light_dir = vec.normalize(3, f32, vec.sub(3, f32, payload.from, hit_pt));
                    const theta = vec.dot(3, f32, light_dir, opposite);
                    const eps = payload.cutoff - payload.falloff;
                    const intensity = math.clamp((theta - payload.falloff) / eps, 0.0, 1.0);
                    break :blk .{
                        light_dir,
                        @as(Real(3), @splat(intensity)),
                        light.common.attenuate(&material, dist),
                        std.math.inf(f32),
                    };
                },
            };

        const shadow_ray = Ray{ .origin = hit_pt, .direction = light_dir };
        if (world.objHit(&shadow_ray, 0.0001, shadow_max)) |_| return @splat(0);

        const glossiness = attenuated.glossiness;
        const specular = attenuated.specular;
        const diffuse = attenuated.diffuse;

        const half_vector = vec.normalize(3, f32, view + light_dir);
        const n_dot_h = vec.dot(3, f32, normal, half_vector);
        const n_dot_l = vec.dot(3, f32, normal, light_dir);

        return intensity * vec.mul_scalar(3, f32, @max(0, n_dot_l), diffuse) +
            intensity * vec.mul_scalar(3, f32, math.pow(f32, @max(0, n_dot_h), glossiness), specular);
    }
};
