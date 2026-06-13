const std = @import("std");
const testing = std.testing;

const vec = @import("vec");
const Real = vec.Real;

const Material = @import("Material.zig");
const Ray = @import("Ray.zig");

const Object = @This();

const log = std.log.scoped(.object);

tag: Tag,
common: Common,

pub const Tag = enum {
    sphere,
    triangle,
    plane,
};

pub const Common = struct {
    extra_idx: u32 = 0,
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
            t += (h + sqrtd) / a;
            if (t < tmin or t > tmax) return null;
        }
        const normal = (@as(Real(3), r.at(t)) - @as(Real(3), self.center)) / @as(Real(3), @splat(self.radius));

        return .{ .t = t, .normal = normal };
    }
};

pub const Triangle = struct {
    v1: [3]f32,
    v2: [3]f32,
    v3: [3]f32,

    pub fn hit(self: *const Triangle, r: *const Ray, tmin: f32, tmax: f32) ?Hit {
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

        return .{ .t = t, .normal = vec.normalize(3, f32, vec.cross3(f32, e1, e2)) };
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
};

pub const Raw = struct {
    inner: union(Tag) {
        sphere: Sphere,
        triangle: Triangle,
        plane: Plane.Raw,
    },
    material: ?[]const u8 = null,

    pub fn intoInternal(self: @This()) Raw {
        return self;
    }
};
