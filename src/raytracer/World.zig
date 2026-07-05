const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const MultiArrayList = std.MultiArrayList;
const eql = std.mem.eql;

const obj = @import("obj");
const pre = @import("pre");
const vec = @import("vec");

const Color = @import("Color.zig");
const lerp = @import("lerp.zig");
const Light = @import("Light.zig");
const Point = Light.Point;
const Directional = Light.Directional;
const Spotlight = Light.Spotlight;
const Material = @import("Material.zig");
const Blinn = Material.Blinn;
const Flat = Material.Flat;
const Object = @import("Object.zig");
const Plane = Object.Plane;
const Sphere = Object.Sphere;
const Mesh = Object.Mesh;
const Ray = @import("Ray.zig");

const World = @This();

background: Background = .{ .single_color = .{} },
materials: Materials = .{},
objects: Objects = .{},
lights: Lights = .{},

pub fn deinit(self: *@This(), gpa: Allocator) void {
    self.objects.deinit(gpa);
    self.materials.deinit(gpa);
    self.lights.deinit(gpa);
}

pub const Hit = struct {
    t: f32,
    normal: [3]f32,
    material: Material,
};

pub fn objHit(self: *const World, r: *const Ray, max_dist: f32) ?Hit {
    const tmin = 0;
    var tmax = max_dist;
    var closest_hit: ?Hit = null;

    const slice = self.objects.list.slice();
    const tags = slice.items(.tag);
    const commons = slice.items(.common);
    for (tags, commons) |tag, c| {
        const hit = switch (tag) {
            .sphere => self.objects.spheres.items[c.extra_idx].hit(r, tmin, tmax),
            .plane => self.objects.planes.items[c.extra_idx].hit(r, tmin, tmax),
            .mesh => b: {
                const mesh = self.objects.meshes.get(c.extra_idx);
                const attrs = self.objects.mesh_attrs.items[mesh.attrs];
                break :b mesh.hit(&attrs, r, tmin, tmax);
            },
        } orelse continue;
        const material = switch (tag) {
            .mesh => self.objects.meshes.get(c.extra_idx).materials[hit.face],
            else => c.material,
        };
        closest_hit = .{
            .t = hit.t,
            .normal = hit.normal,
            .material = self.materials.list.get(material),
        };
        tmax = hit.t;
    }
    return closest_hit orelse null;
}

pub const Raw = struct {
    background: Background.Raw = .{ .single_color = .{ .color = .{ .hex = "#ffffff" } } },
    materials: []Material.Raw = &.{},
    objects: []Object.Raw = &.{},
    lights: []Light.Raw = &.{},
    obj_files: []const []const u8 = &.{},

    pub fn intoInternal(self: @This(), gpa: Allocator, source_path: []const u8) !World {
        var world: World = .{};
        errdefer world.deinit(gpa);

        world.background = try self.background.intoInternal();
        world.materials = try .fromRawList(gpa, self.materials);
        world.objects = try .fromRawList(gpa, self.objects, &world.materials);
        world.lights = try .fromRawList(gpa, self.lights);

        for (self.obj_files) |f| {
            const path = try pre.resolvePath(gpa, source_path, f);
            try world.loadObjFile(gpa, path);
        }

        if (world.materials.list.len == 0 and world.objects.list.len > 0) {
            std.log.err("objects have no material defined", .{});
            return error.NoMaterial;
        }

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

const Materials = struct {
    list: MultiArrayList(Material) = .empty,
    blinn: ArrayList(Blinn) = .empty,
    flat: ArrayList(Flat) = .empty,

    fn deinit(self: *@This(), gpa: Allocator) void {
        for (self.list.items(.name)) |n| gpa.free(n);
        self.list.deinit(gpa);
        self.blinn.deinit(gpa);
        self.flat.deinit(gpa);
    }

    fn appendRaw(self: *@This(), gpa: Allocator, raw: Material.Raw) !void {
        const names = self.list.items(.name);
        for (names) |name| {
            if (std.mem.eql(u8, name, raw.name)) {
                std.log.err("duplicate material '{s}'", .{name});
                return error.DuplicateMaterial;
            }
        }
        var mat: Material = .{ .tag = raw.inner, .name = raw.name };
        switch (raw.inner) {
            .flat => |f| {
                mat.extra_idx = @intCast(self.flat.items.len);
                try self.flat.append(gpa, try .fromRaw(f));
            },
            .blinn => |b| {
                mat.extra_idx = @intCast(self.blinn.items.len);
                try self.blinn.append(gpa, b);
            },
        }
        try self.list.append(gpa, mat);
    }

    fn fromRawList(gpa: Allocator, raw: []const Material.Raw) !@This() {
        var this = @This(){};
        errdefer this.deinit(gpa);
        for (raw) |r| try this.appendRaw(gpa, r);
        return this;
    }
};

const Objects = struct {
    list: MultiArrayList(Object) = .empty,

    spheres: ArrayList(Sphere) = .empty,
    planes: ArrayList(Plane) = .empty,
    meshes: MultiArrayList(Mesh) = .empty,
    mesh_attrs: ArrayList(Mesh.Attributes) = .empty,

    const obj_log = std.log.scoped(.@"world.objects");

    fn deinit(self: *@This(), gpa: Allocator) void {
        self.list.deinit(gpa);
        self.spheres.deinit(gpa);
        self.planes.deinit(gpa);
        for (self.meshes.items(.indices)) |i| gpa.free(i);
        for (self.mesh_attrs.items) |a| {
            gpa.free(a.vertices);
            gpa.free(a.normals);
        }
        self.meshes.deinit(gpa);
        self.mesh_attrs.deinit(gpa);
    }

    fn fromRawList(gpa: Allocator, raw_objs: []const Object.Raw, materials: *Materials) !Objects {
        var this = @This(){};
        errdefer this.deinit(gpa);
        try this.list.ensureUnusedCapacity(gpa, raw_objs.len);

        for (raw_objs) |raw| {
            var new: Object = .{ .tag = raw.inner.intoTag() };
            if (raw.material) |raw_material| {
                var found = false;
                const names = materials.list.items(.name);
                for (names, 0..) |n, i| {
                    if (eql(u8, n, raw_material)) {
                        new.common.material = @intCast(i);
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    obj_log.err("unknown material name: {s}", .{raw_material});
                    return error.UnknownMaterial;
                }
            }
            switch (raw.inner) {
                .sphere => |s| {
                    new.common.extra_idx = @intCast(this.spheres.items.len);
                    try this.spheres.append(gpa, s);
                },
                .plane => |p| {
                    new.common.extra_idx = @intCast(this.planes.items.len);
                    try this.planes.append(gpa, p.intoInternal());
                },
            }
            this.list.appendAssumeCapacity(new);
        }

        return this;
    }
};

const Lights = struct {
    list: MultiArrayList(Light) = .empty,
    directional: ArrayList(Directional) = .empty,
    point: ArrayList(Point) = .empty,
    spotlight: ArrayList(Spotlight) = .empty,

    fn deinit(self: *Lights, gpa: Allocator) void {
        self.list.deinit(gpa);
        self.directional.deinit(gpa);
        self.point.deinit(gpa);
        self.spotlight.deinit(gpa);
    }

    fn fromRawList(gpa: Allocator, raw_lights: []const Light.Raw) !Lights {
        var this: Lights = .{};
        errdefer this.deinit(gpa);

        for (raw_lights) |raw| {
            // SAFETY: `extra_idx` is defined by the switch below.
            var extra_idx: u32 = undefined;
            switch (raw.inner) {
                .ambient => {},
                .directional => |d| {
                    extra_idx = @intCast(this.directional.items.len);
                    try this.directional.append(gpa, d);
                },
                .point => |p| {
                    extra_idx = @intCast(this.point.items.len);
                    try this.point.append(gpa, p);
                },
                .spotlight => |p| {
                    var l = p;
                    l.cutoff = @cos(vec.angleToRad(p.cutoff));
                    l.falloff = @cos(vec.angleToRad(p.falloff));
                    extra_idx = @intCast(this.spotlight.items.len);
                    try this.spotlight.append(gpa, l);
                },
            }

            var item = try raw.intoInternal();
            item.common.extra_idx = extra_idx;
            try this.list.append(gpa, item);
        }
        return this;
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
