const std = @import("std");
const Allocator = std.mem.Allocator;
const MultiArrayList = std.MultiArrayList;
const ArrayList = std.ArrayList;
const math = std.math;
const testing = std.testing;

const pre = @import("pre");
const obj = @import("obj");
const vec = @import("vec");
const Real = vec.Real;

const Material = @import("Material.zig");
const Ray = @import("Ray.zig");

const Object = @This();

tag: Tag,
common: Common = .{},

pub const Tag = enum {
    sphere,
    plane,
    mesh,
};

pub const Common = struct {
    extra_idx: u32 = 0,
    // FIX: Having this field 0 as default is not ideal, one can skip specifying
    // a material and the program will silently use the first one available.
    material: u32 = 0,
};

pub const List = struct {
    list: MultiArrayList(Object) = .empty,
    spheres: ArrayList(Sphere) = .empty,
    planes: ArrayList(Plane) = .empty,
    meshes: MultiArrayList(Mesh) = .empty,
    mesh_attrs: ArrayList(Mesh.Attributes) = .empty,

    pub fn deinit(self: *List, gpa: Allocator) void {
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

    pub fn fromRaw(
        gpa: Allocator,
        raw: []const Object.Raw,
        materials: *Material.List,
        source_path: []const u8,
    ) !List {
        var this = @This(){};
        errdefer this.deinit(gpa);
        try this.list.ensureUnusedCapacity(gpa, raw.len);
        for (raw) |r| try this.appendRawAssumeCapacity(gpa, r, materials, source_path);
        return this;
    }

    fn appendRawAssumeCapacity(
        self: *List,
        gpa: Allocator,
        raw: Object.Raw,
        materials: *Material.List,
        source_path: []const u8,
    ) !void {
        var new: Object = .{ .tag = raw.inner.intoTag() };
        if (raw.material) |raw_material| {
            var found = false;
            const names = materials.list.items(.name);
            for (names, 0..) |n, i| {
                if (std.mem.eql(u8, n, raw_material)) {
                    new.common.material = @intCast(i);
                    found = true;
                    break;
                }
            }
            if (!found) {
                std.log.err("unknown material name: {s}", .{raw_material});
                return error.UnknownMaterial;
            }
        }
        switch (raw.inner) {
            .sphere => |s| {
                new.common.extra_idx = @intCast(self.spheres.items.len);
                try self.spheres.append(gpa, s);
            },
            .plane => |p| {
                new.common.extra_idx = @intCast(self.planes.items.len);
                try self.planes.append(gpa, p.intoInternal());
            },
            .mesh => |m| {
                const path = try pre.resolvePath(gpa, source_path, m);
                try self.loadObjFile(gpa, materials, path);
                return;
            },
        }
        self.list.appendAssumeCapacity(new);
    }

    pub fn loadObjFile(
        self: *List,
        gpa: Allocator,
        materials: *Material.List,
        filename: []const u8,
    ) !void {
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
        try self.mesh_attrs.append(gpa, mesh_attrs);
        try materials.list.ensureUnusedCapacity(gpa, scene.num_materials);
        try materials.blinn.ensureUnusedCapacity(gpa, scene.num_materials);
        try self.meshes.ensureUnusedCapacity(gpa, scene.num_shapes);
        try self.list.ensureUnusedCapacity(gpa, scene.num_shapes);

        @memcpy(mesh_attrs.vertices, scene.attrib.vertices.ptr);
        @memcpy(mesh_attrs.normals, scene.attrib.normals.ptr);

        const material_offset: u32 = @intCast(materials.list.len);

        // Add the materials.
        for (0..scene.num_materials) |m| {
            const material = scene.materials[m];
            const new: Material = .{
                .tag = .blinn,
                .extra_idx = @intCast(materials.blinn.items.len),
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
            materials.list.appendAssumeCapacity(new);
            materials.blinn.appendAssumeCapacity(blinn);
        }

        // Add the meshes.
        for (0..scene.num_shapes) |s| {
            const tobj_mesh = scene.shapes[s].mesh;
            const new: Object = .{
                .tag = .mesh,
                .common = .{ .extra_idx = @intCast(self.meshes.len) },
            };
            const mesh: Mesh = .{
                .attrs = @intCast(self.mesh_attrs.items.len - 1),
                .indices = try gpa.alloc(Mesh.Idx, tobj_mesh.num_indices),
                .materials = try gpa.alloc(u32, tobj_mesh.num_faces),
            };
            self.list.appendAssumeCapacity(new);
            self.meshes.appendAssumeCapacity(mesh);

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

    /// A bound of an object and a reference to the object in the list.
    pub const Bounded = struct {
        bounds: Bounds,
        ref: u32,
    };

    /// Returns the amount of objects that can be bounded.
    ///
    /// For example, meshes and spheres can be bounded but planes no.
    pub fn boundableCount(self: *const List) usize {
        return self.list.len - self.planes.items.len;
    }

    /// Bounds all the objects inside the list and returns an owned slice with all the bounds.
    ///
    /// This is useful for pre-calculating the bounds during BVH tree builds.
    pub fn boundAll(self: *const List, gpa: Allocator) ![]Bounded {
        const slice = self.list.slice();
        const meshes = self.meshes.slice();
        const bounded = try gpa.alloc(Bounded, self.boundableCount());
        var idx: u32 = 0;
        for (0..slice.len) |i| {
            const object = slice.get(i);
            // We cannot bound infinite planes so it's impossible to pre-calculate this.
            if (object.tag == .plane) continue;

            bounded[idx].bounds = switch (object.tag) {
                .sphere => self.spheres.items[object.common.extra_idx].bounds(),
                .mesh => blk: {
                    const mesh = meshes.get(object.common.extra_idx);
                    const attrs = self.mesh_attrs.items[mesh.attrs];
                    break :blk mesh.bounds(&attrs);
                },
                else => unreachable,
            };
            bounded[idx].ref = @intCast(i);
            idx += 1;
        }
        return bounded;
    }
};

pub const Bounds = struct {
    pmin: [3]f32 = @splat(math.inf(f32)),
    pmax: [3]f32 = @splat(-math.inf(f32)),

    /// Determines if a ray hits the bounding box or no.
    ///
    /// The algorithm is the slab method based on https://tavianator.com/2022/ray_box_boundary.html.
    pub fn hits(
        self: *const Bounds,
        r: *const Ray,
        inv_dir: Real(3),
        tmax: f32,
    ) bool {
        var tmin: f32 = 0.0;
        const t1 = vec.sub(3, f32, self.pmin, r.origin) * inv_dir;
        const t2 = vec.sub(3, f32, self.pmax, r.origin) * inv_dir;
        inline for (0..3) |d| tmin = @max(tmin, @min(@min(t1[d], t2[d]), tmax));
        return tmin < tmax;
    }

    pub fn diagonal(self: *const Bounds) [3]f32 {
        return vec.sub(3, f32, self.pmax, self.pmin);
    }

    pub fn maxDimension(self: *const Bounds) u8 {
        const d = self.diagonal();
        if (d[0] > d[1] and d[0] > d[2])
            return 0;
        if (d[1] > d[2])
            return 1;
        return 2;
    }

    pub fn merge(self: *const Bounds, other: *const Bounds) Bounds {
        return .{
            .pmin = @min(@as(Real(3), self.pmin), @as(Real(3), other.pmin)),
            .pmax = @max(@as(Real(3), self.pmax), @as(Real(3), other.pmax)),
        };
    }

    pub fn centroid(self: *const Bounds) [3]f32 {
        return vec.mul_scalar(3, f32, 0.5, @as(Real(3), self.pmin) + self.pmax);
    }

    /// Normalizes a coordinate inside the bounds.
    pub fn offset(self: *const Bounds, v: Real(3)) [3]f32 {
        var o = v - self.pmin;
        if (self.pmax[0] > self.pmin[0])
            o[0] /= self.pmax[0] - self.pmin[0];
        if (self.pmax[1] > self.pmin[1])
            o[1] /= self.pmax[1] - self.pmin[1];
        if (self.pmax[2] > self.pmin[2])
            o[2] /= self.pmax[2] - self.pmin[2];
        return o;
    }

    pub fn surfaceArea(self: *const Bounds) f32 {
        const diag: Real(3) = vec.sub(3, f32, self.pmax, self.pmin);
        return 2 * (diag[0] * diag[1] + diag[0] * diag[2] + diag[1] * diag[2]);
    }
};

pub const Sphere = struct {
    center: [3]f32 = .{ -1.0, 0.5, 5.0 },
    radius: f32 = 0.4,

    pub fn hit(self: *const Sphere, r: *const Ray, tmin: f32, tmax: f32) ?Hit {
        const oc = @as(Real(3), self.center) - @as(Real(3), r.origin);
        const a = vec.dot(3, f32, r.direction, r.direction);
        const h = vec.dot(3, f32, r.direction, oc);
        const c = vec.dot(3, f32, oc, oc) - self.radius * self.radius;
        const discriminant = h * h - a * c;
        if (discriminant < 1e-8) return null;

        const sqrtd = @sqrt(discriminant);
        var t = (h - sqrtd) / a;
        if (t < tmin or t > tmax) {
            t = (h + sqrtd) / a;
            if (t < tmin or t > tmax) return null;
        }
        const normal = (@as(Real(3), r.at(t)) - @as(Real(3), self.center)) / @as(Real(3), @splat(self.radius));

        return .{ .t = t, .normal = normal };
    }

    pub fn bounds(self: *const Sphere) Bounds {
        return .{
            .pmin = self.center - @as(Real(3), @splat(self.radius)),
            .pmax = self.center + @as(Real(3), @splat(self.radius)),
        };
    }
};

pub const Mesh = struct {
    indices: []Idx,
    materials: []u32,
    attrs: u32,

    pub const Attributes = struct {
        vertices: []f32,
        normals: []f32,
    };

    pub const Idx = struct {
        vertex: usize,
        normal: usize,
    };

    const Triangle = struct {
        v1: [3]f32,
        v2: [3]f32,
        v3: [3]f32,

        /// Tries to find a intersection with a ray using Möller-Trumbore algorithm.
        fn hit(
            self: *const @This(),
            r: *const Ray,
            tmin: f32,
            tmax: f32,
        ) ?struct { t: f32, beta: f32, gamma: f32 } {
            const e1 = @as(Real(3), self.v2) - @as(Real(3), self.v1);
            const e2 = @as(Real(3), self.v3) - @as(Real(3), self.v1);

            const pvec = vec.cross3(f32, r.direction, e2);
            const det = vec.dot(3, f32, e1, pvec);
            if (@abs(det) < 1e-8) return null;
            const inv_det = 1.0 / det;

            const svec = @as(Real(3), r.origin) - @as(Real(3), self.v1);
            const beta = vec.dot(3, f32, svec, pvec) * inv_det;
            if (beta < 0 or beta > 1) return null;

            const qvec = vec.cross3(f32, svec, e1);
            const gamma = vec.dot(3, f32, r.direction, qvec) * inv_det;
            if (gamma < 0 or beta + gamma > 1.0) return null;

            const t = vec.dot(3, f32, e2, qvec) * inv_det;
            if (t < tmin or t > tmax) return null;

            return .{ .t = t, .beta = beta, .gamma = gamma };
        }
    };

    pub fn hit(
        self: *const Mesh,
        attrs: *const Attributes,
        r: *const Ray,
        tmin: f32,
        tmax: f32,
    ) ?Hit {
        var max = tmax;
        var result: ?Hit = null;
        for (0..self.indices.len / 3) |i| {
            const tri = self.triangle(attrs, i);
            if (tri.hit(r, tmin, max)) |v| {
                max = v.t;
                const n0 = self.indices[i * 3].normal * 3;
                const n1 = self.indices[i * 3 + 1].normal * 3;
                const n2 = self.indices[i * 3 + 2].normal * 3;
                const alpha = 1.0 - v.beta - v.gamma;
                var interp: [3]f32 = undefined;
                for (&interp, 0..) |*comp, j| {
                    comp.* =
                        alpha * attrs.normals[n0 + j] +
                        v.beta * attrs.normals[n1 + j] +
                        v.gamma * attrs.normals[n2 + j];
                }
                result = .{
                    .t = v.t,
                    .normal = vec.normalize(3, f32, @as(Real(3), interp)),
                    .face = i,
                };
            }
        }
        return result;
    }

    fn triangle(self: *const Mesh, attrs: *const Attributes, idx: usize) Mesh.Triangle {
        return .{
            .v1 = attrs.vertices[self.indices[idx * 3].vertex * 3 ..][0..3].*,
            .v2 = attrs.vertices[self.indices[idx * 3 + 1].vertex * 3 ..][0..3].*,
            .v3 = attrs.vertices[self.indices[idx * 3 + 2].vertex * 3 ..][0..3].*,
        };
    }

    pub fn bounds(self: *const Mesh, attrs: *const Attributes) Bounds {
        var min: Real(3) = @splat(math.inf(f32));
        var max: Real(3) = @splat(-math.inf(f32));
        for (self.indices) |i| {
            const v: Real(3) = attrs.vertices[i.vertex * 3 ..][0..3].*;
            min = @min(min, v);
            max = @max(max, v);
        }
        return .{ .pmin = min, .pmax = max };
    }
};

pub const Plane = struct {
    pos: [3]f32,
    normal: [3]f32,

    const Raw = struct {
        pos: [3]f32,
        dir: [3]f32,

        pub fn intoInternal(self: @This()) Plane {
            return .{
                .pos = self.pos,
                .normal = vec.normalize(3, f32, self.dir),
            };
        }
    };

    pub fn hit(self: *const Plane, r: *const Ray, tmin: f32, tmax: f32) ?Hit {
        const rdir_dot_pnorm = vec.dot(3, f32, r.direction, self.normal);
        if (rdir_dot_pnorm == 0) return null;

        const t = vec.dot(3, f32, @as(Real(3), self.pos) - @as(Real(3), r.origin), self.normal) / rdir_dot_pnorm;
        if (t < tmin or t > tmax) return null;

        return .{ .t = t, .normal = self.normal };
    }
};

pub const Hit = struct {
    t: f32,
    normal: [3]f32,
    face: usize = 0,
};

pub const Raw = struct {
    // TODO: Make this material override the mesh material.
    material: ?[]const u8 = null,
    inner: union(enum) {
        sphere: Sphere,
        plane: Plane.Raw,
        mesh: []const u8,

        pub fn intoTag(self: @This()) Tag {
            return switch (self) {
                .sphere => .sphere,
                .plane => .plane,
                .mesh => .mesh,
            };
        }
    },

    pub fn intoInternal(self: @This()) Raw {
        return self;
    }
};

fn expectVecApproxEq(expected: [3]f32, actual: [3]f32) !void {
    for (expected, actual) |e, a| {
        try testing.expectApproxEqAbs(e, a, 1e-6);
    }
}

test "object list: boundAll returns owned empty slice" {
    const objects = Object.List{};

    const bounded = try objects.boundAll(testing.allocator);
    defer testing.allocator.free(bounded);

    try testing.expectEqual(@as(usize, 0), bounded.len);
}

test "sphere: ray from outside hits nearest surface" {
    const sphere = Sphere{ .center = .{ 0, 0, 5 }, .radius = 1 };
    const ray = Ray{ .origin = .{ 0, 0, 0 }, .direction = .{ 0, 0, 1 } };

    const hit = sphere.hit(&ray, 0, 100) orelse return error.TestExpectedHit;

    try testing.expectApproxEqAbs(@as(f32, 4), hit.t, 1e-6);
    try expectVecApproxEq(.{ 0, 0, -1 }, hit.normal);
}

test "sphere: ray from inside hits far surface" {
    const sphere = Sphere{ .center = .{ 0, 0, 0 }, .radius = 1 };
    const ray = Ray{ .origin = .{ 0, 0, 0 }, .direction = .{ 0, 0, 1 } };

    const hit = sphere.hit(&ray, 0.001, 100) orelse return error.TestExpectedHit;

    try testing.expectApproxEqAbs(@as(f32, 1), hit.t, 1e-6);
    try expectVecApproxEq(.{ 0, 0, 1 }, hit.normal);
}

test "sphere: ray miss returns null" {
    const sphere = Sphere{ .center = .{ 0, 0, 5 }, .radius = 1 };
    const ray = Ray{ .origin = .{ 0, 0, 0 }, .direction = .{ 0, 1, 0 } };

    try testing.expectEqual(null, sphere.hit(&ray, 0, 100));
}

test "sphere: hit outside t range returns null" {
    const sphere = Sphere{ .center = .{ 0, 0, 5 }, .radius = 1 };
    const ray = Ray{ .origin = .{ 0, 0, 0 }, .direction = .{ 0, 0, 1 } };

    try testing.expectEqual(null, sphere.hit(&ray, 0, 3));
}

const Triangle = Mesh.Triangle;

test "triangle: ray hits interior" {
    const triangle = Triangle{
        .v1 = .{ -1, -1, 5 },
        .v2 = .{ 1, -1, 5 },
        .v3 = .{ 0, 1, 5 },
    };
    const ray = Ray{ .origin = .{ 0, 0, 0 }, .direction = .{ 0, 0, 1 } };

    const hit = triangle.hit(&ray, 0, 100) orelse return error.TestExpectedHit;

    try testing.expectApproxEqAbs(@as(f32, 5), hit.t, 1e-6);
}

test "triangle: ray outside barycentric region misses" {
    const triangle = Triangle{
        .v1 = .{ -1, -1, 5 },
        .v2 = .{ 1, -1, 5 },
        .v3 = .{ 0, 1, 5 },
    };
    const ray = Ray{ .origin = .{ 2, 0, 0 }, .direction = .{ 0, 0, 1 } };

    try testing.expectEqual(null, triangle.hit(&ray, 0, 100));
}

test "triangle: parallel ray misses" {
    const triangle = Triangle{
        .v1 = .{ -1, -1, 5 },
        .v2 = .{ 1, -1, 5 },
        .v3 = .{ 0, 1, 5 },
    };
    const ray = Ray{ .origin = .{ 0, 0, 0 }, .direction = .{ 1, 0, 0 } };

    try testing.expectEqual(null, triangle.hit(&ray, 0, 100));
}

test "plane: ray hits plane" {
    const plane = Plane{ .pos = .{ 0, 0, 5 }, .normal = .{ 0, 0, 1 } };
    const ray = Ray{ .origin = .{ 0, 0, 0 }, .direction = .{ 0, 0, 1 } };

    const hit = plane.hit(&ray, 0, 100) orelse return error.TestExpectedHit;

    try testing.expectApproxEqAbs(@as(f32, 5), hit.t, 1e-6);
    try expectVecApproxEq(.{ 0, 0, 1 }, hit.normal);
}

test "plane: parallel ray misses" {
    const plane = Plane{ .pos = .{ 0, 0, 5 }, .normal = .{ 0, 0, 1 } };
    const ray = Ray{ .origin = .{ 0, 0, 0 }, .direction = .{ 1, 0, 0 } };

    try testing.expectEqual(null, plane.hit(&ray, 0, 100));
}

test "plane raw: intoInternal normalizes direction" {
    const plane = (Plane.Raw{ .pos = .{ 0, 0, 0 }, .dir = .{ 0, 0, 2 } }).intoInternal();

    try expectVecApproxEq(.{ 0, 0, 1 }, plane.normal);
}
