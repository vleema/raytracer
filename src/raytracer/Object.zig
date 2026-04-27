const std = @import("std");
const eql = std.mem.eql;
const ArrayList = std.ArrayList;
const MultiArrayList = std.MultiArrayList;
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

    pub fn fromStr(str: []const u8) !@This() {
        if (eql(u8, str, "sphere")) return .sphere;
        log.err("expected one of ['sphere'], found '{s}'", .{str});
        return error.InvalidObjectTag;
    }
};

pub const Common = struct {
    extra_idx: usize = 0,
};

pub const Sphere = struct {
    center: [3]f64 = .{ -1.0, 0.5, 5.0 },
    radius: f64 = 0.4,

    pub fn hit(self: *const @This(), r: *const Ray, tmin: f64, tmax: f64) ?Hit {
        const oc = @as(Real(3), self.center) - @as(Real(3), r.origin);
        const a = vec.dot(3, f64, r.direction, r.direction);
        const h = vec.dot(3, f64, r.direction, oc);
        const c = vec.dot(3, f64, oc, oc) - self.radius * self.radius;
        const discriminant = h * h - a * c;
        if (discriminant < 0) return null;

        const sqrtd = @sqrt(discriminant);
        var t = (h - sqrtd) / a;
        if (t <= tmin or tmax <= t) {
            t += (h + sqrtd) / a;
            if (t <= tmin or tmax <= t) return null;
        }
        const normal = (@as(Real(3), r.at(t)) - @as(Real(3), self.center)) / @as(Real(3), @splat(self.radius));

        return .{ .t = t, .normal = normal };
    }
};

pub const Hit = struct {
    t: f64,
    normal: [3]f64,
};

pub const Raw = struct {
    inner: union(Tag) {
        sphere: Sphere,
    } = .{ .sphere = .{} },

    material: ?union(enum) {
        anon: Material,
        name: []const u8,
    } = null,

    pub fn fromXml(elem: *const xml.Element) !@This() {
        var anon_material = false;
        var this = @This(){};

        const typ = elem.queryAttribute("type", null) orelse {
            log.err("expected object type", .{});
            return error.ExpectedObjectType;
        };

        const tag = try Tag.fromStr(typ);

        switch (tag) {
            .sphere => {
                const radius = elem.queryAttribute("radius", null) orelse {
                    log.err("expected sphere radius in object definition", .{});
                    return error.ExpectedSphereRadius;
                };
                const center = elem.queryAttribute("center", null) orelse {
                    log.err("expected sphere center in object definition", .{});
                    return error.ExpectedSphereCenter;
                };
                this.inner = .{
                    .sphere = .{
                        .radius = try std.fmt.parseFloat(f64, radius),
                        .center = try xml.parseFloatArray(f64, 3, center),
                    },
                };
            },
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

test "sphere with anon material" {
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

test "sphere with nammed material" {
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
