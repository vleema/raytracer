const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const MultiArrayList = std.MultiArrayList;
const eql = std.mem.eql;
const testing = std.testing;

const vec = @import("vec");
const Real = vec.Real;
const xml = @import("xml");

const img = @import("img.zig");
const Color = img.Color;
const Material = @import("Material.zig");
const Object = @import("Object.zig");
const Sphere = Object.Sphere;
const Ray = @import("Ray.zig");

const World = @This();

background: Background = .{ .single_color = .{} },
materials: Materials = .{},
objects: Objects = .{},

const log = std.log.scoped(.world);

pub fn deinit(self: *@This(), gpa: Allocator) void {
    self.objects.deinit(gpa);
    self.materials.deinit(gpa);
}

pub fn fromXml(gpa: Allocator, elem: *const xml.Element) !World {
    var world = @This(){};
    errdefer world.deinit(gpa);
    var raw_objs = Objects.Raw{};
    defer raw_objs.list.deinit(gpa);
    const options = .{
        .background = &world.background,
        .materials = &world.materials,
        .objects = &raw_objs,
    };
    if (try xml.parseChildren(gpa, options, elem)) |unknown| {
        const keys_str = comptime xml.fieldKeysStr(@TypeOf(options));
        log.err("unrecognized option '{s}', expected one of {s}", .{ unknown, keys_str });
        return error.UnrecognizedWorldValue;
    }
    world.objects = try .init(gpa, raw_objs, &world.materials);
    return world;
}

pub fn objHit(self: *const World, r: *const Ray) ?struct { hit: Object.Hit, material: Material } {
    const tmin = 0;
    var tmax = std.math.inf(f64);
    var closest_hit: ?Object.Hit = null;
    var material: ?Material = null;

    const slice = self.objects.list.slice();
    const tags = slice.items(.tag);
    const commons = slice.items(.common);
    for (tags, commons, self.objects.materials.items) |t, c, m| {
        const hit = switch (t) {
            .sphere => self.objects.spheres.items[c.extra_idx].hit(r, tmin, tmax),
        };
        if (hit) |h| {
            closest_hit = h;
            tmax = h.t;
            material = self.materials.list.items[m];
        }
    }

    if (closest_hit != null and material != null) return .{
        .hit = closest_hit.?,
        .material = material.?,
    };

    return null;
}

const Materials = struct {
    list: ArrayList(Material) = .empty,
    names: ArrayList([]const u8) = .empty,

    var anon_idx: usize = 0;

    fn init(gpa: Allocator) !@This() {
        var this = @This(){};
        try this.add(gpa, .{}, "default");
        return this;
    }

    fn deinit(self: *@This(), gpa: Allocator) void {
        for (self.names.items) |n| gpa.free(n);
        self.names.deinit(gpa);
        self.list.deinit(gpa);
    }

    fn add(self: *@This(), gpa: Allocator, m: Material, name: ?[]const u8) !void {
        if (name) |n| {
            try self.names.append(gpa, try gpa.dupe(u8, n));
        } else {
            // FIX: This introduces a bug where the user could type some anon name and generate a conflict.
            try self.names.append(gpa, try std.fmt.allocPrint(gpa, "__anon__{}", .{anon_idx}));
            anon_idx += 1;
        }
        try self.list.append(gpa, m);
    }

    pub fn fromXml(gpa: Allocator, elem: *const xml.Element) !@This() {
        var ret = try @This().init(gpa);
        errdefer ret.deinit(gpa);
        var node = elem.values.first;
        while (node) |n| : (node = n.next) {
            const m: *const xml.Element = @fieldParentPtr("node", n);
            if (!eql(u8, m.key, "material")) continue;
            const name = if (m.queryAttribute("name", null)) |name|
                name
            else {
                log.err("material name is obligatory", .{});
                return error.ExpectedMaterialName;
            };
            try ret.add(gpa, try .fromXml(m), name);
        }
        return ret;
    }
};

const Objects = struct {
    list: MultiArrayList(Object) = .empty,
    materials: ArrayList(u16) = .empty,

    spheres: ArrayList(Sphere) = .empty,

    fn init(gpa: Allocator, raw: Objects.Raw, materials: *Materials) !@This() {
        std.debug.assert(materials.list.items.len < std.math.maxInt(u16));

        var this = @This(){};
        errdefer this.deinit(gpa);

        for (raw.list.items(.material)) |r| {
            if (r == null) {
                try this.materials.append(gpa, 0);
                continue;
            }

            switch (r.?) {
                .anon => |material| {
                    try this.materials.append(gpa, @intCast(materials.list.items.len));
                    try materials.add(gpa, material, null);
                },
                .name => |obj_name| {
                    for (materials.names.items, 0..) |material_name, i| {
                        if (eql(u8, material_name, obj_name)) {
                            try this.materials.append(gpa, @intCast(i));
                        }
                    }
                },
            }
        }

        for (raw.list.items(.inner)) |i| {
            var idx: usize = undefined;
            switch (i) {
                .sphere => {
                    idx = this.spheres.items.len;
                    try this.spheres.append(gpa, i.sphere);
                },
            }
            try this.list.append(gpa, .{
                .tag = @as(Object.Tag, i),
                .common = .{ .extra_idx = idx },
            });
        }

        return this;
    }

    fn deinit(self: *@This(), gpa: Allocator) void {
        self.list.deinit(gpa);
        self.spheres.deinit(gpa);
        self.materials.deinit(gpa);
    }

    const Raw = struct {
        list: MultiArrayList(Object.Raw) = .empty,

        pub fn fromXml(gpa: Allocator, elem: *const xml.Element) !@This() {
            var this = @This(){};
            errdefer this.list.deinit(gpa);
            var node = elem.values.first;
            while (node) |n| : (node = n.next) {
                const c: *const xml.Element = @fieldParentPtr("node", n);
                if (!eql(u8, c.key, "object")) continue;
                try this.list.append(gpa, try .fromXml(c));
            }
            return this;
        }
    };
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

    pub fn ptColor(self: *const @This(), width: u32, height: u32, pt: [2]f64) Color {
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

test "world with object list" {
    const str =
        \\ <world>
        \\    <background type="single_color" color="255 0xff 0xf0" />
        \\    <materials>
        \\         <material name="green" type="flat" color="42 201 51"/>
        \\    </materials>
        \\    <objects>
        \\         <object type="sphere" radius="0.4" center="-1 0.5 5" material="green"/>
        \\         <object type="sphere" radius="0.4" center="1 -0.5 8" material_type="flat" material_color="42 42 42"/>
        \\    </objects>
        \\ </world>
    ;
    const background = Background{
        .single_color = .{ .color = .{ .r = 255, .g = 0xff, .b = 0xf0 } },
    };

    const materials = [_]Material{
        .{},
        .{ .typ = .flat, .color = .{ .r = 42, .g = 201, .b = 51 } },
        .{ .typ = .flat, .color = .{ .r = 42, .g = 42, .b = 42 } },
    };

    const objects = [_]Object{
        .{ .tag = .sphere, .common = .{ .extra_idx = 0 } },
        .{ .tag = .sphere, .common = .{ .extra_idx = 1 } },
    };
    const material = [_]u16{ 1, 2 };

    const spheres = [_]Sphere{
        .{ .radius = 0.4, .center = .{ -1.0, 0.5, 5.0 } },
        .{ .radius = 0.4, .center = .{ 1.0, -0.5, 8.0 } },
    };

    var root = try xml.parse(str, testing.allocator);
    defer root.deinit(testing.allocator);

    var actual = try World.fromXml(testing.allocator, &root);
    defer actual.deinit(testing.allocator);

    try testing.expectEqualDeep(background, actual.background);
    try testing.expectEqualDeep(&materials, actual.materials.list.items);

    try testing.expectEqual(objects.len, actual.objects.list.len);
    for (0..actual.objects.list.len) |i| {
        try testing.expectEqualDeep(objects[i], actual.objects.list.get(i));
    }

    try testing.expectEqualDeep(&material, actual.objects.materials.items);
    try testing.expectEqualDeep(&spheres, actual.objects.spheres.items);
}
