const std = @import("std");
const eql = std.mem.eql;
const xml = @import("xml");
const vec = @import("vec");
const Real = vec.Real;
const img = @import("img.zig");
const Color = img.Color;
const Material = @import("Material.zig");
const Object = @import("Object.zig").Object;
const Sphere = @import("Object.zig").Sphere;
const Ray = @import("Ray.zig");

const World = @This();

background: Background = .{ .single_color = .{} },
material: Material = .{},
objects: Objects = .{},

const log = std.log.scoped(.world);

pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
    self.objects.deinit(gpa);
}

pub fn fromXml(gpa: std.mem.Allocator, elem: *const xml.Element) !World {
    var world = @This(){};
    const options = .{
        .background = &world.background,
        .material = &world.material,
        .objects = &world.objects,
    };
    if (try xml.parseChildren(gpa, options, elem)) |unknown| {
        const keys_str = comptime xml.fieldKeysStr(@TypeOf(options));
        log.err("unrecognized option '{s}', expected one of {s}", .{ unknown, keys_str });
        return error.UnrecognizedWorldValue;
    }
    return world;
}

pub fn intersect(self: *const World, r: *const Ray) ?Color {
    for (self.objects.spheres.items) |s| {
        if (s.intersect(r)) return self.material.color;
    }
    return null;
}

const Objects = struct {
    spheres: std.ArrayList(Sphere) = .empty,

    fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        self.spheres.deinit(gpa);
    }

    fn add(self: *@This(), gpa: std.mem.Allocator, obj: Object) !void {
        switch (obj) {
            .sphere => |s| try self.spheres.append(gpa, s),
        }
    }

    pub fn fromXml(gpa: std.mem.Allocator, elem: *const xml.Element) !@This() {
        var ret = @This(){};
        var node = elem.values.first;
        while (node) |n| : (node = n.next) {
            const c: *const xml.Element = @fieldParentPtr("node", n);
            if (!eql(u8, c.key, "object")) continue;
            try ret.add(gpa, try .fromXml(c));
        }
        return ret;
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

    const background_log = std.log.scoped(.background);

    pub fn fromXml(elem: *const xml.Element) !@This() {
        const typ = elem.queryAttribute("type", null) orelse
            return error.ExpectedBackgroundType;

        if (eql(u8, typ, "single_color")) {
            return .{
                .single_color = .{
                    .color = try .fromStr(elem.queryAttribute("color", null)),
                },
            };
        } else if (eql(u8, typ, "4_colors")) {
            return .{
                .four_colors = .{
                    .tl = try .fromStr(elem.queryAttribute("tl", null)),
                    .tr = try .fromStr(elem.queryAttribute("tr", null)),
                    .bl = try .fromStr(elem.queryAttribute("bl", null)),
                    .br = try .fromStr(elem.queryAttribute("br", null)),
                },
            };
        }
        background_log.err("expected one of ['single_color', '4_colors'], found {s}", .{typ});
        return error.InvalidBackgroundType;
    }

    pub fn ptColor(self: *const @This(), width: u32, height: u32, pt: Real(2)) Color {
        return switch (self.*) {
            .single_color => |b| b.color,
            .four_colors => |b| img.bilerp(
                .{ .pos = .{ 0, 0 }, .color = b.tl },
                .{ .pos = .{ width, 0 }, .color = b.tr },
                .{ .pos = .{ 0, height }, .color = b.bl },
                .{ .pos = .{ width, height }, .color = b.br },
                pt,
            ),
        };
    }
};

const testing = std.testing;

test "world: with object list" {
    const str =
        \\ <world>
        \\    <background type="single_color" color="255 0xff 0xf0" />
        \\    <material type="flat" color="0.95 0.05 0.05" />
        \\    <objects>
        \\         <object type="sphere" radius="0.4" center="-1 0.5 5" />
        \\         <object type="sphere" radius="0.4" center="1 -0.5 8" />
        \\    </objects>
        \\ </world>
    ;
    const spheres = [_]Sphere{
        .{ .radius = 0.4, .center = .{ -1.0, 0.5, 5.0 } },
        .{ .radius = 0.4, .center = .{ 1.0, -0.5, 8.0 } },
    };

    var spheres_arr = try std.ArrayList(Sphere).initCapacity(testing.allocator, 2);
    defer spheres_arr.deinit(testing.allocator);
    try spheres_arr.insertSlice(testing.allocator, 0, &spheres);

    const expected = World{
        .material = .{
            .typ = .flat,
            .color = .{ .r = 242, .b = 12, .g = 12 },
        },
        .background = .{
            .single_color = .{
                .color = .{ .r = 255, .g = 0xff, .b = 0xf0 },
            },
        },
        .objects = .{ .spheres = spheres_arr },
    };

    var root = try xml.parse(str, testing.allocator);
    defer root.deinit(testing.allocator);

    var actual = try World.fromXml(testing.allocator, &root);
    defer actual.deinit(testing.allocator);

    try testing.expectEqualDeep(expected.material, actual.material);
    try testing.expectEqualDeep(expected.background, actual.background);
    try testing.expectEqualDeep(expected.objects.spheres.items, actual.objects.spheres.items);
}
