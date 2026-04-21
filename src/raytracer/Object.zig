const std = @import("std");
const eql = std.mem.eql;
const xml = @import("xml");
const vec = @import("vec");
const Real = vec.Real;

const Ray = @import("Ray.zig");

const log = std.log.scoped(.object);

pub const Object = union(enum) {
    sphere: Sphere,

    pub fn fromXml(elem: *const xml.Element) !@This() {
        const typ = elem.queryAttribute("type", null) orelse
            return error.ExpectedObjectType;

        if (eql(u8, typ, "sphere")) return .{ .sphere = try .fromXml(elem) };

        log.err("expected one of ['sphere'], found {s}", .{typ});
        return error.InvalidObjectType;
    }
};

pub const Sphere = struct {
    radius: f64 = 0.4,
    center: Real(3) = .{ -1, -1.5, 3.5 },

    pub fn intersect(self: *const @This(), r: *const Ray) bool {
        const oc = self.center - r.origin;
        const a = vec.dot(3, f64, r.direction, r.direction);
        const b = -2.0 * vec.dot(3, f64, r.direction, oc);
        const c = vec.dot(3, f64, oc, oc) - self.radius * self.radius;
        const discriminant = b * b - 4 * a * c;
        return discriminant >= 0;
    }

    pub fn fromXml(elem: *const xml.Element) !@This() {
        var this = @This(){};
        if (elem.queryAttribute("radius", null)) |v| {
            this.radius = try std.fmt.parseFloat(f64, v);
        }
        if (elem.queryAttribute("center", null)) |v| {
            this.center = try xml.parseFloatArray(f64, 3, v);
        }
        return this;
    }
};

const testing = std.testing;

test "object: sphere" {
    const str =
        \\ <root>
        \\    <object type="sphere" radius="0.4" center="-1 -1.5 3.5" />
        \\ </root>
    ;
    var root = try xml.parse(str, testing.allocator);
    defer root.deinit(testing.allocator);

    const expected = Object{
        .sphere = .{
            .center = .{ -1, -1.5, 3.5 },
            .radius = 0.4,
        },
    };
    const actual = try Object.fromXml(root.firstChildElement("object").?);
    try testing.expectEqualDeep(expected, actual);
}
