const std = @import("std");
const Io = std.Io;
const math = std.math;

const vec = @import("vec");
const Real = vec.Real;

const Camera = @import("camera.zig").Camera;
const Color = @import("Color.zig");
const Frame = @import("Look.zig").Frame;
const Light = @import("Light.zig");
const Material = @import("Material.zig");
const Ray = @import("Ray.zig");
const World = @import("World.zig");

const Tile = struct {
    x_min: u32,
    x_max: u32,
    y_min: u32,
    y_max: u32,
};

pub const Integrator = union(enum) {
    flat: Flat,
    blinn: Blinn,

    pub fn render(
        self: *const Integrator,
        io: std.Io,
        buf: []Color,
        world: *const World,
        camera: *const Camera,
        frame: *const Frame,
        height: u32,
        width: u32,
    ) !void {
        var group: Io.Group = .init;
        errdefer group.cancel(io);
        const tile_size = 16;
        var y: u32 = 0;
        while (y < height) : (y += tile_size) {
            var x: u32 = 0;
            while (x < width) : (x += tile_size) {
                const tile: Tile = .{
                    .x_min = x,
                    .y_min = y,
                    .x_max = @min(x + tile_size, width),
                    .y_max = @min(y + tile_size, height),
                };
                group.async(io, writeTile, .{ self, buf, world, camera, frame, height, width, tile });
            }
        }
        try group.await(io);
    }

    fn writeTile(
        self: *const Integrator,
        buf: []Color,
        world: *const World,
        camera: *const Camera,
        frame: *const Frame,
        img_height: u32,
        img_width: u32,
        tile: Tile,
    ) void {
        for (tile.y_min..tile.y_max) |y| {
            for (tile.x_min..tile.x_max) |x| {
                const ray = camera.generateRay(@intCast(x), @intCast(y), img_width, img_height, frame);
                const color = if (world.hit(&ray, std.math.inf(f32))) |h|
                    self.li(world, ray, h, 0)
                else
                    // TODO: Add texture background.
                    world.background.ptColor(
                        img_width,
                        img_height,
                        .{ @floatFromInt(x), @floatFromInt(y) },
                    );

                buf[x + y * img_width] = color;
            }
        }
    }

    fn li(
        self: *const Integrator,
        world: *const World,
        ray: Ray,
        hit: World.Hit,
        depth: u32,
    ) Color {
        return switch (self.*) {
            inline else => |v| v.li(world, ray, hit, depth),
        };
    }
};

pub const Flat = struct {
    pub fn li(
        _: anytype,
        world: *const World,
        _: anytype,
        hit: World.Hit,
        _: anytype,
    ) Color {
        return switch (hit.material.tag) {
            .flat => world.materials.flat.items[hit.material.extra_idx].color,
            .blinn => .fromReal(world.materials.blinn.items[hit.material.extra_idx].diffuse),
        };
    }
};

pub const Blinn = struct {
    max_depth: u32 = 3,

    pub fn li(
        self: *const Blinn,
        world: *const World,
        ray: Ray,
        hit: World.Hit,
        depth: u32,
    ) Color {
        if (hit.material.tag == .flat) return world.materials.flat.items[hit.material.extra_idx].color;
        const blinn = world.materials.blinn.items[hit.material.extra_idx];

        const view: Real(3) = -@as(Real(3), ray.direction);
        const hit_pt = ray.at(hit.t);

        var light_contrib: Real(3) = .{ 0, 0, 0 };
        const slice = world.lights.list.slice();
        for (slice.items(.tag), slice.items(.common)) |tag, common| {
            const light: Light = .{ .common = common, .tag = tag };
            light_contrib += lightContrib(world, light, view, hit.normal, hit_pt, blinn);
        }
        if (depth < self.max_depth) {
            const direction = ray.direction -
                vec.mul_scalar(3, f32, 2 * vec.dot(3, f32, ray.direction, hit.normal), hit.normal);
            const reflect_origin = hit_pt + @as(Real(3), @splat(0.001)) * hit.normal;
            const reflected: Ray = .{ .direction = direction, .origin = reflect_origin };
            if (world.hit(&reflected, math.inf(f32))) |h| {
                light_contrib += blinn.mirror * self.li(world, reflected, h, depth + 1).toReal();
            }
        }
        return .fromReal(light_contrib);
    }

    fn lightContrib(
        world: *const World,
        light: Light,
        view: Real(3),
        normal: Real(3),
        hit_pt: [3]f32,
        material: Material.Blinn,
    ) Real(3) {
        const light_dir, const intensity, const attenuated, const shadow_max =
            switch (light.tag) {
                .ambient => return vec.mul(3, f32, .{
                    material.ambient,
                    light.common.intensity,
                }),
                // TODO: Use bouding box as shadow ray.
                .directional => blk: {
                    const payload = world.lights.directional.items[light.common.extra_idx];
                    const light_dir = vec.normalize(3, f32, vec.sub(3, f32, payload.from, payload.to));
                    break :blk .{
                        light_dir,
                        light.common.intensity,
                        material,
                        math.inf(f32),
                    };
                },
                .point => blk: {
                    const payload = world.lights.point.items[light.common.extra_idx];
                    const light_dir = vec.normalize(3, f32, vec.sub(3, f32, payload.from, hit_pt));
                    const light_dist = vec.len(3, f32, vec.sub(3, f32, payload.from, hit_pt));
                    break :blk .{
                        light_dir,
                        light.common.intensity,
                        light.common.attenuate(&material, light_dist),
                        light_dist,
                    };
                },
                .spotlight => blk: {
                    const payload = world.lights.spotlight.items[light.common.extra_idx];
                    const opposite = vec.normalize(3, f32, vec.sub(3, f32, payload.from, payload.to));
                    const light_dir = vec.normalize(3, f32, vec.sub(3, f32, payload.from, hit_pt));
                    const light_dist = vec.len(3, f32, vec.sub(3, f32, payload.from, hit_pt));
                    const theta = vec.dot(3, f32, light_dir, opposite);
                    const eps = payload.falloff - payload.cutoff;
                    const intensity = math.clamp((theta - payload.cutoff) / eps, 0.0, 1.0);
                    break :blk .{
                        light_dir,
                        light.common.intensity * @as(Real(3), @splat(intensity)),
                        light.common.attenuate(&material, light_dist),
                        light_dist,
                    };
                },
            };

        const shadow_origin = hit_pt + @as(Real(3), @splat(0.001)) * normal;
        const shadow_ray = Ray{ .origin = shadow_origin, .direction = light_dir };
        if (world.hit(&shadow_ray, shadow_max)) |_| return @splat(0);

        const glossiness = attenuated.glossiness;
        const specular = attenuated.specular;
        const diffuse = attenuated.diffuse;

        const half_vector = vec.normalize(3, f32, view + light_dir);
        const n_dot_h = vec.dot(3, f32, normal, half_vector);
        const n_dot_l = vec.dot(3, f32, normal, light_dir);

        const diffuse_contrib = intensity * vec.mul_scalar(3, f32, @max(0, n_dot_l), diffuse);
        const specular_contrib = if (glossiness > 0)
            intensity *
                vec.mul_scalar(3, f32, math.pow(f32, @max(0, n_dot_h), glossiness), specular)
        else
            @as(Real(3), @splat(0));

        return diffuse_contrib + specular_contrib;
    }
};
