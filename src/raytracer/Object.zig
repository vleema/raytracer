const std = @import("std");
const eql = std.mem.eql;
const testing = std.testing;

const vec = @import("vec");
const Real = vec.Real;
const xml = @import("xml");

const Material = @import("Material.zig");
const Ray = @import("Ray.zig");

const Object = @This();

const log = std.log.scoped(.object);

tag: Tag,
common: Common,

pub const Tag = enum {
    sphere,
    triangle,

    pub fn fromStr(str: []const u8) !@This() {
        if (eql(u8, str, "sphere")) return .sphere;
        if (eql(u8, str, "triangle")) return .triangle;

        log.err("expected one of ['sphere', 'triangle'], found '{s}'", .{str});
        return error.InvalidObjectTag;
    }
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

    pub fn fromXml(elem: *const xml.Element) !Sphere {
        const radius = elem.queryAttribute("radius", null) orelse {
            log.err("expected sphere radius in object definition", .{});
            return error.ExpectedSphereRadius;
        };
        const center = elem.queryAttribute("center", null) orelse {
            log.err("expected sphere center in object definition", .{});
            return error.ExpectedSphereCenter;
        };
        return .{
            .radius = try std.fmt.parseFloat(f32, radius),
            .center = try xml.parseFloatArray(f32, 3, center),
        };
    }
};

pub const Triangle = struct {
    v1: [3]f32,
    v2: [3]f32,
    v3: [3]f32,

    pub fn hit(self: *const Triangle, r: *const Ray, tmin: f32, tmax: f32) ?Hit {
        // Möller Trumbore algorithm.
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

    pub fn fromXml(elem: *const xml.Element) !Triangle {
        const v1 = elem.queryAttribute("v1", null) orelse {
            log.err("expected 'v1' vertice for triangle object", .{});
            return error.ExpectedTriangleVertice;
        };
        const v2 = elem.queryAttribute("v2", null) orelse {
            log.err("expected 'v2' vertice for triangle object", .{});
            return error.ExpectedTriangleVertice;
        };
        const v3 = elem.queryAttribute("v3", null) orelse {
            log.err("expected 'v3' vertice for triangle object", .{});
            return error.ExpectedTriangleVertice;
        };

        return .{
            .v1 = try xml.parseFloatArray(f32, 3, v1),
            .v2 = try xml.parseFloatArray(f32, 3, v2),
            .v3 = try xml.parseFloatArray(f32, 3, v3),
        };
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
    },

    material: ?union(enum) {
        anon: Material,
        name: []const u8,
    } = null,

    pub fn fromXml(elem: *const xml.Element) !Raw {
        var anon_material = false;
        // SAFETY: `this.inner` is initialized just after.
        var this: Raw = .{ .inner = undefined };

        const typ = elem.queryAttribute("type", null) orelse {
            log.err("expected object type", .{});
            return error.ExpectedObjectType;
        };

        const tag = try Tag.fromStr(typ);
        switch (tag) {
            .sphere => this.inner = .{ .sphere = try .fromXml(elem) },
            .triangle => this.inner = .{ .triangle = try .fromXml(elem) },
        }

        if (elem.queryAttribute("material_type", null)) |t| {
            this.material =
                if (elem.queryAttribute("material_color", null)) |c|
                    .{ .anon = .{ .typ = try .fromStr(t), .color = try .fromStr(c) } }
                else
                    .{ .anon = .{ .typ = try .fromStr(t) } };
            anon_material = true;
        }
        if (elem.queryAttribute("material", null)) |m| {
            if (anon_material) {
                log.err("'material' and ['material_type', 'material_color'] options cannot coexist", .{});
                return error.DuplicateMaterialType;
            }
            this.material = .{ .name = m };
        }

        return this;
    }
};

test "fromXml: sphere with anon material" {
    const str =
        \\ <root>
        \\    <object type="sphere" radius="0.4" center="-1 -1.5 3.5" material_type="flat" material_color="42 201 51" />
        \\ </root>
    ;
    var root = try xml.parse(str, testing.allocator);
    defer root.deinit(testing.allocator);

    const expected = Raw{
        .inner = .{
            .sphere = .{
                .radius = 0.4,
                .center = .{ -1, -1.5, 3.5 },
            },
        },
        .material = .{
            .anon = .{
                .typ = .flat,
                .color = .{ .r = 42, .g = 201, .b = 51 },
            },
        },
    };
    const actual = try Raw.fromXml(root.firstChildElement("object").?);
    try testing.expectEqualDeep(expected.inner, actual.inner);
    try testing.expectEqualDeep(expected.material, actual.material);
}

test "fromXml: sphere with nammed material" {
    const str =
        \\ <root>
        \\    <object type="sphere" radius="0.4" center="-1 -1.5 3.5" material="green" />
        \\ </root>
    ;
    var root = try xml.parse(str, testing.allocator);
    defer root.deinit(testing.allocator);

    const expected = Object.Raw{
        .inner = .{
            .sphere = .{
                .radius = 0.4,
                .center = .{ -1.0, -1.5, 3.5 },
            },
        },
        .material = .{ .name = "green" },
    };
    const actual = try Object.Raw.fromXml(root.firstChildElement("object").?);
    try testing.expectEqualDeep(expected.inner, actual.inner);
    try testing.expectEqualDeep(expected.material, actual.material);
}

test "fromXml: triangle" {
    const str =
        \\ <root>
        \\    <object type="triangle" v1="1 2 3" v2="4 5 6" v3="7 8 9" />
        \\ </root>
    ;
    var root = try xml.parse(str, testing.allocator);
    defer root.deinit(testing.allocator);

    const expected = Raw{
        .inner = .{
            .triangle = .{
                .v1 = .{ 1, 2, 3 },
                .v2 = .{ 4, 5, 6 },
                .v3 = .{ 7, 8, 9 },
            },
        },
        .material = null,
    };
    const actual = try Raw.fromXml(root.firstChildElement("object").?);
    try testing.expectEqualDeep(expected.inner, actual.inner);
    try testing.expectEqualDeep(expected.material, actual.material);
}
