const std = @import("std");
const eql = std.mem.eql;

const xml = @import("xml");

const vec = @import("vec");
const Real = vec.Real;

const img = @import("img.zig");
const Color = img.Color;
const bilerp = img.bilerp;

const Material = @import("Material.zig");

background: Background = .{ .single_color = .{} },
material: Material = .{},
objects: ObjectList = .{},

const log = std.log.scoped(.world);

pub fn fromXml(allocator: std.mem.Allocator, elem: *const xml.Element) !@This() {
    var world = @This(){};
    const options = .{
        .background = &world.background,
        .material = &world.material,
    };
    if (try xml.parseChildren(allocator, options, elem)) |unknown| {
        const keys_str = comptime xml.fieldKeysStr(@TypeOf(options));
        log.err("unrecognized option '{s}', expected one of {s}", .{ unknown, keys_str });
        return error.UnrecognizedWorldValue;
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
