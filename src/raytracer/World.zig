const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const MultiArrayList = std.MultiArrayList;
const eql = std.mem.eql;
const testing = std.testing;

const Color = @import("Color.zig");
const lerp = @import("lerp.zig");
const Light = @import("Light.zig");
const Ambient = Light.Ambient;
const Point = Light.Point;
const Directional = Light.Directional;
const Material = @import("Material.zig");
const Blinn = Material.Blinn;
const Object = @import("Object.zig");
const Plane = Object.Plane;
const Sphere = Object.Sphere;
const Triangle = Object.Triangle;
const Ray = @import("Ray.zig");

const World = @This();

background: Background = .{ .single_color = .{} },
materials: Materials = .{},
objects: Objects = .{},
lights: Lights = .{},

const log = std.log.scoped(.world);

pub fn deinit(self: *@This(), gpa: Allocator) void {
    self.objects.deinit(gpa);
    self.materials.deinit(gpa);
    self.lights.deinit(gpa);
}

pub fn objHit(self: *const World, r: *const Ray) ?struct { hit: Object.Hit, material: Material } {
    const tmin = 0;
    var tmax = std.math.inf(f32);
    var closest_hit: ?Object.Hit = null;
    var material: ?Material = null;

    const slice = self.objects.list.slice();
    const tags = slice.items(.tag);
    const commons = slice.items(.common);
    for (tags, commons, self.objects.materials.items) |t, c, m| {
        const hit = switch (t) {
            .sphere => self.objects.spheres.items[c.extra_idx].hit(r, tmin, tmax),
            .triangle => self.objects.triangles.items[c.extra_idx].hit(r, tmin, tmax),
            .plane => self.objects.planes.items[c.extra_idx].hit(r, tmin, tmax),
        };
        if (hit) |h| {
            closest_hit = h;
            tmax = h.t;
            material = self.materials.list.items[m];
        }
    }

    if (closest_hit != null and material != null) return .{
        .hit = closest_hit.?,
        .material = material.?,
    };

    return null;
}

const Materials = struct {
    list: ArrayList(Material) = .empty,
    names: ArrayList([]const u8) = .empty,

    blinn: ArrayList(Blinn) = .empty,

    fn deinit(self: *@This(), gpa: Allocator) void {
        for (self.names.items) |n| gpa.free(n);
        self.names.deinit(gpa);
        self.list.deinit(gpa);
        self.blinn.deinit(gpa);
    }

    fn add(self: *@This(), gpa: Allocator, raw: Material.Raw) !void {
        try self.names.append(gpa, try gpa.dupe(u8, raw.name));
        var mat = try raw.intoInternal();
        switch (raw.inner) {
            .flat => {},
            .blinn => |b| {
                mat.common.extra_idx = @intCast(self.blinn.items.len);
                try self.blinn.append(gpa, b);
            },
        }
        try self.list.append(gpa, mat);
    }

    fn fromRawList(gpa: Allocator, raw: []const Material.Raw) !@This() {
        var this = @This(){};
        errdefer this.deinit(gpa);
        for (raw) |r| try this.add(gpa, r);
        return this;
    }
};

const Objects = struct {
    list: MultiArrayList(Object) = .empty,
    materials: ArrayList(u16) = .empty,

    spheres: ArrayList(Sphere) = .empty,
    triangles: ArrayList(Triangle) = .empty,
    planes: ArrayList(Plane) = .empty,

    const obj_log = std.log.scoped(.@"world.objects");

    fn deinit(self: *@This(), gpa: Allocator) void {
        self.list.deinit(gpa);
        self.spheres.deinit(gpa);
        self.triangles.deinit(gpa);
        self.planes.deinit(gpa);
        self.materials.deinit(gpa);
    }

    fn fromRawList(gpa: Allocator, raw_objs: []const Object.Raw, materials: *Materials) !Objects {
        std.debug.assert(materials.list.items.len < std.math.maxInt(u16));

        var this = @This(){};
        errdefer this.deinit(gpa);

        for (raw_objs) |raw| {
            if (raw.material) |raw_name| {
                var found = false;
                for (materials.names.items, 0..) |int_name, i| {
                    if (eql(u8, int_name, raw_name)) {
                        found = true;
                        try this.materials.append(gpa, @intCast(i));
                    }
                }
                if (!found) {
                    obj_log.err("unknown material name: {s}", .{raw_name});
                    return error.UnknownMaterial;
                }
            } else {
                try this.materials.append(gpa, 0);
            }
        }

        for (raw_objs) |raw| {
            var idx: u32 = undefined;
            switch (raw.inner) {
                .sphere => |s| {
                    idx = @intCast(this.spheres.items.len);
                    try this.spheres.append(gpa, s);
                },
                .triangle => |t| {
                    idx = @intCast(this.triangles.items.len);
                    try this.triangles.append(gpa, t);
                },
                .plane => |p| {
                    idx = @intCast(this.planes.items.len);
                    try this.planes.append(gpa, p.intoInternal());
                },
            }
            try this.list.append(gpa, .{
                .tag = @as(Object.Tag, raw.inner),
                .common = .{ .extra_idx = idx },
            });
        }

        return this;
    }
};

const Lights = struct {
    list: MultiArrayList(Light) = .empty,
    directional: ArrayList(Directional) = .empty,
    point: ArrayList(Point) = .empty,

    fn deinit(self: *Lights, gpa: Allocator) void {
        self.list.deinit(gpa);
        self.directional.deinit(gpa);
        self.point.deinit(gpa);
    }

    fn fromRawList(gpa: Allocator, raw_lights: []const Light.Raw) !Lights {
        var this: Lights = .{};
        errdefer this.deinit(gpa);

        for (raw_lights) |raw| {
            var item = raw;
            switch (item.inner) {
                .ambient => {},
                .directional => |d| {
                    item.common.extra_idx = @intCast(this.directional.items.len);
                    try this.directional.append(gpa, d);
                },
                .point => |p| {
                    item.common.extra_idx = @intCast(this.point.items.len);
                    try this.point.append(gpa, p);
                },
            }
            try this.list.append(gpa, .{
                .tag = @as(Light.Tag, item.inner),
                .common = item.common,
            });
        }
        return this;
    }
};

pub const Background = union(enum) {
    single_color: struct {
        color: Color = .{},
    },
    four_colors: struct {
        tl: Color = .{},
        tr: Color = .{},
        bl: Color = .{},
        br: Color = .{},
    },

    pub fn ptColor(self: *const @This(), width: u32, height: u32, pt: [2]f32) Color {
        return switch (self.*) {
            .single_color => |b| b.color,
            .four_colors => |b| lerp.bilerp(
                .{ .pos = .{ 0, 0 }, .color = b.tl },
                .{ .pos = .{ width, 0 }, .color = b.tr },
                .{ .pos = .{ 0, height }, .color = b.bl },
                .{ .pos = .{ width, height }, .color = b.br },
                pt,
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
                        .color = try s.color.intoInternal(),
                    },
                },
                .four_colors => |f| .{ .four_colors = .{
                    .tl = try f.tl.intoInternal(),
                    .tr = try f.tr.intoInternal(),
                    .bl = try f.bl.intoInternal(),
                    .br = try f.br.intoInternal(),
                } },
            };
        }
    };
};

pub const Raw = struct {
    background: Background.Raw = .{ .single_color = .{ .color = .{ .hex = "#ffffff" } } },
    materials: []Material.Raw = &.{},
    objects: []Object.Raw = &.{},
    lights: []Light.Raw = &.{},

    pub fn intoInternal(self: @This(), gpa: Allocator) !World {
        var world: World = .{};
        errdefer world.deinit(gpa);

        world.background = try self.background.intoInternal();
        world.materials = try .fromRawList(gpa, self.materials);
        world.objects = try .fromRawList(gpa, self.objects, &world.materials);
        world.lights = try .fromRawList(gpa, self.lights);

        return world;
    }
};
