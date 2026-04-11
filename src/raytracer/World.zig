const xml = @import("xml");

const std = @import("std");
const eql = std.mem.eql;

const vec = @import("vec");
const Real = vec.Real;

const img = @import("img.zig");
const Color = img.Color;
const bilerp = img.bilerp;

background: Background = .{ .single_color = .{} },

const log = std.log.scoped(.world);

pub fn fromXml(elem: *const xml.Element) !@This() {
    var world = @This(){};
    var node = elem.values.first;
    while (node) |n| {
        const val: *const xml.Element = @fieldParentPtr("node", n);
        node = n.next;

        if (eql(u8, val.key, "background")) {
            world.background = try @TypeOf(world.background).fromXml(val);
        } else {
            log.err("expected 'background' tag, found {s}", .{val.key});
            return error.UnknownTag;
        }
    }
    return world;
}

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
