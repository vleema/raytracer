const std = @import("std");
const eql = std.mem.eql;

const xml = @import("xml");

const vec = @import("vec");
const Real = vec.Real;

const img = @import("img.zig");
const Color = img.Color;
const Material = @import("Material.zig");
const Object = @import("Object.zig").Object;
const Ray = @import("Ray.zig");

const World = @This();

background: Background = .{ .single_color = .{} },
material: Material = .{},
objects: ObjectList = .{},

const log = std.log.scoped(.world);

pub fn fromXml(allocator: std.mem.Allocator, elem: *const xml.Element) !World {
    var world = @This(){};
    const options = .{
        .background = &world.background,
        .material = &world.material,
        .objects = &world.objects,
    };
    if (try xml.parseChildren(allocator, options, elem)) |unknown| {
        const keys_str = comptime xml.fieldKeysStr(@TypeOf(options));
        log.err("unrecognized option '{s}', expected one of {s}", .{ unknown, keys_str });
        return error.UnrecognizedWorldValue;
    }
    return world;
}

pub fn intersect(self: *const World, r: *const Ray) ?Color {
    var node = self.objects.list.first;
    while (node) |n| : (node = n.next) {
        const obj: *const ObjectNode = @alignCast(@fieldParentPtr("node", n));
        if (obj.object.intersect(r)) return self.material.color;
    }
    return null;
}

pub fn deinit(self: *World, allocator: std.mem.Allocator) void {
    while (self.objects.list.popFirst()) |n| {
        const ptr: *ObjectNode = @alignCast(@fieldParentPtr("node", n));
        allocator.destroy(ptr);
    }
}

const ObjectNode = struct {
    object: Object,
    node: std.DoublyLinkedList.Node = .{},
};

const ObjectList = struct {
    const Self = @This();

    list: std.DoublyLinkedList = .{},

    pub fn fromXml(allocator: std.mem.Allocator, elem: *const xml.Element) !@This() {
        var list = std.DoublyLinkedList{};
        var node = elem.values.first;
        while (node) |n| : (node = n.next) {
            const c: *const xml.Element = @fieldParentPtr("node", n);
            if (!eql(u8, c.key, "object")) continue;
            const ptr = try allocator.create(ObjectNode);
            ptr.*.object = try .fromXml(c);
            list.append(&ptr.node);
        }
        return ObjectList{ .list = list };
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
    var obj1 = ObjectNode{
        .object = .{
            .sphere = .{ .radius = 0.4, .center = .{ -1.0, 0.5, 5.0 } },
        },
    };
    var obj2 = ObjectNode{
        .object = .{
            .sphere = .{ .radius = 0.4, .center = .{ 1.0, -0.5, 8.0 } },
        },
    };
    var objs = ObjectList{};
    objs.list.append(&obj1.node);
    objs.list.append(&obj2.node);
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
        .objects = objs,
    };

    var root = try xml.parse(str, testing.allocator);
    defer root.deinit(testing.allocator);
    var actual = try World.fromXml(testing.allocator, &root);
    defer actual.deinit(testing.allocator);

    try testing.expectEqualDeep(expected.material, actual.material);
    try testing.expectEqualDeep(expected.background, actual.background);
    try expecEqualObjectList(expected.objects, actual.objects);
}

fn expecEqualObjectList(
    expected: ObjectList,
    actual: ObjectList,
) !void {
    try testing.expectEqual(expected.list.len(), expected.list.len());
    var e = expected.list.first;
    var a = actual.list.first;
    while (e != null and a != null) : ({
        e = e.?.next;
        a = a.?.next;
    }) {
        const ee: *ObjectNode = @alignCast(@fieldParentPtr("node", e.?));
        const ae: *ObjectNode = @alignCast(@fieldParentPtr("node", a.?));
        try testing.expectEqualDeep(ee.object, ae.object);
    }
}
