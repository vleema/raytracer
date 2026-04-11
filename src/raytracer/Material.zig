const xml = @import("xml");
const std = @import("std");
const eql = std.mem.eql;

const img = @import("img.zig");
const Color = img.Color;

const Material = @This();

color: Color = .{},
typ: enum { flat } = .flat,

pub fn fromXml(elem: *const xml.Element) !@This() {
    var ret = @This(){};

    const typ = elem.queryAttribute("type", null) orelse
        return error.ExpectedMaterialType;
    if (eql(u8, typ, "flat")) {
        ret.typ = .flat;
    }

    if (elem.queryAttribute("color", null)) |v| {
        ret.color = try .fromStr(v);
    }

    return ret;
}

const testing = std.testing;

test "from xml" {
    const str =
        \\ <root>
        \\      <material type="flat" color="0.95 0.05 0.05"/>
        \\ </root>
    ;
    var root = try xml.parse(str, testing.allocator);
    defer root.deinit(testing.allocator);

    const expected = Material{
        .color = .{ .r = 242, .b = 12, .g = 12 },
        .typ = .flat,
    };
    const actual = Material.fromXml(root.firstChildElement("material").?);
    try testing.expectEqualDeep(expected, actual);
}
