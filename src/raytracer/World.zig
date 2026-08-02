const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;

const obj = @import("obj");
const pre = @import("pre");

const Bvh = @import("Bvh.zig");
const Color = @import("Color.zig");
const Light = @import("Light.zig");
const Material = @import("Material.zig");
const Object = @import("Object.zig");
const Mesh = Object.Mesh;
const Ray = @import("Ray.zig");

const World = @This();

background: Background = .{ .single_color = .{} },
materials: Material.List = .{},
objects: Object.List = .{},
lights: Light.List = .{},
aggregator: Aggregator = .bvh,
bvh: Bvh = .{},

const Aggregator = enum { bvh, list };

pub fn deinit(self: *World, gpa: Allocator) void {
    self.objects.deinit(gpa);
    self.materials.deinit(gpa);
    self.lights.deinit(gpa);
    self.bvh.deinit(gpa);
}

pub const Hit = struct {
    t: f32,
    normal: [3]f32,
    material: Material,
};

pub fn hit(self: *const World, r: *const Ray, max_dist: f32) ?Hit {
    return switch (self.aggregator) {
        .bvh => self.hitBvh(r, max_dist),
        .list => self.hitList(r, max_dist),
    };
}

fn hitBvh(self: *const World, r: *const Ray, max_dist: f32) ?Hit {
    var closest_hit = self.bvh.hit(Hit, self, World.hitObj, self.objects, r, max_dist);
    var tmax = if (closest_hit) |v|
        v.t
    else
        max_dist;

    // FIX: This is unfortunate, we shouldn't need to iterate all over again just for the planes...
    const objects = self.objects.list.slice();
    const tags = objects.items(.tag);
    const commons = objects.items(.common);
    for (tags, commons) |t, c| {
        if (t != .plane) continue;
        const h = self.objects.planes.items[c.extra_idx].hit(r, 0, tmax) orelse continue;
        tmax = h.t;
        closest_hit = .{
            .t = h.t,
            .normal = h.normal,
            .material = self.materials.list.get(c.material),
        };
    }

    return closest_hit;
}

fn hitList(self: *const World, r: *const Ray, max_dist: f32) ?Hit {
    const tmin = 0;
    var tmax = max_dist;
    var closest_hit: ?Hit = null;

    const slice = self.objects.list.slice();
    const tags = slice.items(.tag);
    const commons = slice.items(.common);
    for (tags, commons) |tag, c| {
        const h = self.hitObj(&Object{ .tag = tag, .common = c }, r, tmin, tmax) orelse continue;
        closest_hit = h;
        tmax = h.t;
    }
    return closest_hit orelse null;
}

pub fn hitObj(
    self: *const World,
    object: *const Object,
    r: *const Ray,
    tmin: f32,
    tmax: f32,
) ?Hit {
    const h = switch (object.tag) {
        .sphere => self.objects.spheres.items[object.common.extra_idx].hit(r, tmin, tmax),
        .plane => self.objects.planes.items[object.common.extra_idx].hit(r, tmin, tmax),
        .triangle => b: {
            const triangle = self.objects.triangles.items[object.common.extra_idx];
            const mesh = self.objects.meshes.get(triangle.mesh);
            const attrs = self.objects.mesh_attrs.items[mesh.attrs];
            break :b mesh.hit(&attrs, triangle.idx, r, tmin, tmax);
        },
    } orelse return null;
    return .{
        .t = h.t,
        .normal = h.normal,
        .material = self.materials.list.get(object.common.material),
    };
}

pub const Raw = struct {
    background: Background.Raw = .{ .single_color = .{ .color = .{ .hex = "#ffffff" } } },
    materials: []Material.Raw = &.{},
    objects: []Object.Raw = &.{},
    lights: []Light.Raw = &.{},
    aggregator: Aggregator = .bvh,

    pub fn intoInternal(
        self: @This(),
        gpa: Allocator,
        io: std.Io,
        source_path: []const u8,
    ) !World {
        var world: World = .{};
        errdefer world.deinit(gpa);

        world.background = try self.background.intoInternal();
        world.materials = try .fromRaw(gpa, self.materials);
        world.objects = try .fromRaw(gpa, io, self.objects, &world.materials, source_path);
        world.lights = try .fromRaw(gpa, self.lights);
        world.aggregator = self.aggregator;

        if (world.materials.list.len == 0 and world.objects.list.len > 0) {
            std.log.err("objects have no material defined", .{});
            return error.NoMaterial;
        }

        if (world.aggregator == .bvh)
            world.bvh = try .build(gpa, &world.objects);

        return world;
    }
};

const Background = union(enum) {
    single_color: struct {
        color: Color = .{},
    },
    four_colors: struct {
        tl: Color = .{},
        tr: Color = .{},
        bl: Color = .{},
        br: Color = .{},
    },

    pub fn pointColor(self: *const @This(), width: u32, height: u32, point: [2]f32) Color {
        return switch (self.*) {
            .single_color => |b| b.color,
            .four_colors => |b| Color.Pixel.interpolate(
                .{ .position = .{ 0, 0 }, .color = b.tl },
                .{ .position = .{ width, 0 }, .color = b.tr },
                .{ .position = .{ 0, height }, .color = b.bl },
                .{ .position = .{ width, height }, .color = b.br },
                point,
            ),
        };
    }

    pub const Raw = union(enum) {
        single_color: struct {
            color: Color.Raw,
        },
        four_colors: struct {
            tl: Color.Raw,
            tr: Color.Raw,
            bl: Color.Raw,
            br: Color.Raw,
        },

        pub fn intoInternal(self: @This()) !Background {
            return switch (self) {
                .single_color => |s| .{
                    .single_color = .{
                        .color = try .fromRaw(s.color),
                    },
                },
                .four_colors => |f| .{ .four_colors = .{
                    .tl = try .fromRaw(f.tl),
                    .tr = try .fromRaw(f.tr),
                    .bl = try .fromRaw(f.bl),
                    .br = try .fromRaw(f.br),
                } },
            };
        }
    };
};
