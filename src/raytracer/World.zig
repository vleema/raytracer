const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;

const obj = @import("obj");
const pre = @import("pre");

const Bvh = @import("Bvh.zig");
const Color = @import("Color.zig");
const lerp = @import("lerp.zig");
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

pub fn deinit(self: *@This(), gpa: Allocator) void {
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
        .mesh => b: {
            const mesh = self.objects.meshes.get(object.common.extra_idx);
            const attrs = self.objects.mesh_attrs.items[mesh.attrs];
            break :b mesh.hit(&attrs, r, tmin, tmax);
        },
    } orelse return null;

    const material = switch (object.tag) {
        .mesh => self.objects.meshes.get(object.common.extra_idx).materials[h.face],
        else => object.common.material,
    };

    return .{
        .t = h.t,
        .normal = h.normal,
        .material = self.materials.list.get(material),
    };
}

pub const Raw = struct {
    background: Background.Raw = .{ .single_color = .{ .color = .{ .hex = "#ffffff" } } },
    materials: []Material.Raw = &.{},
    objects: []Object.Raw = &.{},
    lights: []Light.Raw = &.{},
    obj_files: []const []const u8 = &.{},
    aggregator: Aggregator = .bvh,

    pub fn intoInternal(self: @This(), gpa: Allocator, source_path: []const u8) !World {
        var world: World = .{};
        errdefer world.deinit(gpa);

        world.background = try self.background.intoInternal();
        world.materials = try .fromRaw(gpa, self.materials);
        world.objects = try .fromRaw(gpa, self.objects, &world.materials);
        world.lights = try .fromRaw(gpa, self.lights);
        world.aggregator = self.aggregator;

        for (self.obj_files) |f| {
            const path = try pre.resolvePath(gpa, source_path, f);
            try world.loadObjFile(gpa, path);
        }

        if (world.materials.list.len == 0 and world.objects.list.len > 0) {
            std.log.err("objects have no material defined", .{});
            return error.NoMaterial;
        }

        if (world.aggregator == .bvh)
            world.bvh = try .build(gpa, &world.objects);

        return world;
    }
};

pub fn loadObjFile(self: *World, gpa: Allocator, filename: []const u8) !void {
    var scene: obj.tobj_scene_f = .{};
    var cfg = obj.tobj_default_config();
    var diag: obj.tobj_diag = .{};

    defer obj.tobj_scene_free_f(&scene);
    defer obj.tobj_diag_free(&diag, null);

    if (obj.tobj_load_obj_from_file_f(&scene, @ptrCast(filename), &cfg, &diag) != obj.TOBJ_OK) {
        if (diag.err != null) std.log.err("{s}", .{diag.err});
        return error.ErrorLoadingObjFile;
    }

    // Load the meshes attributes.
    const mesh_attrs: Mesh.Attributes = .{
        .vertices = try gpa.alloc(f32, scene.attrib.vertices.count),
        .normals = try gpa.alloc(f32, scene.attrib.normals.count),
    };
    try self.objects.mesh_attrs.append(gpa, mesh_attrs);
    try self.materials.list.ensureUnusedCapacity(gpa, scene.num_materials);
    try self.materials.blinn.ensureUnusedCapacity(gpa, scene.num_materials);
    try self.objects.meshes.ensureUnusedCapacity(gpa, scene.num_shapes);
    try self.objects.list.ensureUnusedCapacity(gpa, scene.num_shapes);

    @memcpy(mesh_attrs.vertices, scene.attrib.vertices.ptr);
    @memcpy(mesh_attrs.normals, scene.attrib.normals.ptr);

    const material_offset: u32 = @intCast(self.materials.list.len);

    // Add the materials to the world.
    for (0..scene.num_materials) |m| {
        const material = scene.materials[m];
        const new: Material = .{
            .tag = .blinn,
            .extra_idx = @intCast(self.materials.blinn.items.len),
            .name = try gpa.dupe(u8, std.mem.span(material.name)),
        };
        const blinn: Material.Blinn = .{
            // TODO: Add support for the other obj file fields.
            .ambient = material.ambient,
            .diffuse = material.diffuse,
            .specular = material.specular,
            .mirror = @splat(material.metallic), // NOTE: There's no mirror field in the mtl repr.
            .glossiness = 1 - material.roughness,
        };
        // FIX: Append a namespace or sort a merge strategy for materials names.
        self.materials.list.appendAssumeCapacity(new);
        self.materials.blinn.appendAssumeCapacity(blinn);
    }

    // Add the meshes.
    for (0..scene.num_shapes) |s| {
        const tobj_mesh = scene.shapes[s].mesh;
        const new: Object = .{
            .tag = .mesh,
            .common = .{ .extra_idx = @intCast(self.objects.meshes.len) },
        };
        const mesh: Mesh = .{
            .attrs = @intCast(self.objects.mesh_attrs.items.len - 1),
            .indices = try gpa.alloc(Mesh.Idx, tobj_mesh.num_indices),
            .materials = try gpa.alloc(u32, tobj_mesh.num_faces),
        };
        self.objects.list.appendAssumeCapacity(new);
        self.objects.meshes.appendAssumeCapacity(mesh);

        for (0..tobj_mesh.num_indices) |i| {
            mesh.indices[i] = .{
                .vertex = @intCast(tobj_mesh.indices[i].vertex_index),
                .normal = @intCast(tobj_mesh.indices[i].normal_index),
            };
        }
        for (0..tobj_mesh.num_faces) |f| {
            const material_id = tobj_mesh.material_ids[f];
            mesh.materials[f] =
                if (tobj_mesh.material_ids[f] != -1)
                    @as(u32, @intCast(material_id)) + material_offset
                else
                    0;
        }
    }
}

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
