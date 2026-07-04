const std = @import("std");
const testing = std.testing;

const vec = @import("vec");
const Real = vec.Real;

const Ray = @import("Ray.zig");

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

pub const Sphere = struct {
    center: [3]f32 = .{ -1.0, 0.5, 5.0 },
    radius: f32 = 0.4,

    pub fn hit(self: *const @This(), r: *const Ray, tmin: f32, tmax: f32) ?Hit {
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

    pub const Triangle = struct {
        v1: [3]f32,
        v2: [3]f32,
        v3: [3]f32,

        /// Tries to find a intersection with a ray using Möller-Trumbore algorithm.
        pub fn hit(
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

    pub fn triangle(self: *const Mesh, attrs: *const Attributes, idx: usize) Mesh.Triangle {
        return .{
            .v1 = attrs.vertices[self.indices[idx * 3].vertex * 3 ..][0..3].*,
            .v2 = attrs.vertices[self.indices[idx * 3 + 1].vertex * 3 ..][0..3].*,
            .v3 = attrs.vertices[self.indices[idx * 3 + 2].vertex * 3 ..][0..3].*,
        };
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
    inner: union(enum) {
        sphere: Sphere,
        plane: Plane.Raw,

        pub fn intoTag(self: @This()) Tag {
            return switch (self) {
                .sphere => .sphere,
                .plane => .plane,
            };
        }
    },
    material: ?[]const u8 = null,

    pub fn intoInternal(self: @This()) Raw {
        return self;
    }
};

fn expectVecApproxEq(expected: [3]f32, actual: [3]f32) !void {
    for (expected, actual) |e, a| {
        try testing.expectApproxEqAbs(e, a, 1e-6);
    }
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
