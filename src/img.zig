// TODO: Document this properly.

const std = @import("std");
const xml = @import("xml");

pub const Scene = struct {
    camera: struct {} = .{},
    film: Film = .{},
    world: World = .{},

    pub fn fromFile(file: std.fs.File) !Scene {
        var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const md = try file.stat();
        const mmap = try std.posix.mmap(null, md.size, std.posix.PROT.READ, .{ .TYPE = .PRIVATE }, file.handle, 0);
        defer std.posix.munmap(mmap);
        const root = try xml.parse(mmap, arena_allocator);

        var scene: Scene = .{};
        var node = root.values.first;
        while (node) |n| {
            const elem: *xml.Element = @fieldParentPtr("node", n);
            node = n.next;
            if (std.mem.eql(u8, elem.key, "camera"))
                std.log.warn("camera tag still not supported", .{})
            else if (std.mem.eql(u8, elem.key, "film"))
                scene.film = try @TypeOf(scene.film).fromXml(elem)
            else if (std.mem.eql(u8, elem.key, "world_begin"))
                scene.world, node = try @TypeOf(scene.world).fromXml(elem)
            else {
                std.log.err("unrecognized option {s}", .{elem.key});
                return error.UnrecognizedOption;
            }
        }
        return scene;
    }

    /// Returns the color of a background pixel using bilinear interpolation.
    pub fn backgroundPixelColor(self: *const @This(), pt: UnsignedPoint(2)) Color {
        return switch (self.world.background) {
            .single_color => |b| b.color,
            .four_colors => |b| bilerp(
                .{ .pos = .{ 0, 0 }, .color = b.tl },
                .{ .pos = .{ self.film.width, 0 }, .color = b.tr },
                .{ .pos = .{ 0, self.film.height }, .color = b.bl },
                .{ .pos = .{ self.film.width, self.film.height }, .color = b.br },
                pt,
            ),
        };
    }

    pub fn render(self: *const @This(), x: usize, y: usize) [3]u8 {
        const color = self.backgroundPixelColor(.{ x, y });
        return .{ color.r, color.g, color.b };
    }
};

pub const Film = struct {
    typ: enum { image } = .image,
    width: usize = 400,
    height: usize = 200,
    filename: []const u8 = "out.ppm",
    img_type: enum { ppm, png } = .ppm,

    const film_log = std.log.scoped(.film);
    var filename_buf: [256]u8 = undefined;

    fn fromXml(elem: *const xml.Element) !@This() {
        var film = @This(){};

        if (elem.queryAttribute("type", null)) |typ| {
            if (std.mem.eql(u8, "image", typ))
                film.typ = .image
            else
                return error.InvalidFilmType;
        }

        if (elem.queryAttribute("width", null)) |x|
            film.width = try std.fmt.parseUnsigned(usize, x, 10);

        if (elem.queryAttribute("height", null)) |y|
            film.height = try std.fmt.parseUnsigned(usize, y, 10);

        if (elem.queryAttribute("filename", null)) |n| {
            std.mem.copyForwards(u8, &filename_buf, n);
            film.filename = filename_buf[0..n.len];
        }

        if (elem.queryAttribute("img_type", null)) |typ| {
            if (std.mem.eql(u8, "ppm", typ)) {
                film.img_type = .ppm;
            } else if (std.mem.eql(u8, "png", typ)) {
                film.img_type = .png;
            } else {
                return error.InvalidImgType;
            }
        }

        return film;
    }
};

const World = struct {
    background: Background = .{ .single_color = .{} },

    const world_log = std.log.scoped(.world);

    fn fromXml(elem: *const xml.Element) !struct { @This(), ?*std.DoublyLinkedList.Node } {
        var world = @This(){};
        var iter = elem;
        return while (iter.nextSiblingElement()) |next| {
            defer iter = next;
            if (std.mem.eql(u8, next.key, "world_end")) {
                break .{ world, next.node.next };
            }
            if (std.mem.eql(u8, next.key, "background")) {
                world.background = try @TypeOf(world.background).fromXml(next);
            } else {
                world_log.err("expected 'background' tag, found {s}", .{next.key});
                break error.UnknownTag;
            }
        } else blk: {
            world_log.err("expected 'world_end' tag after 'world_begin'", .{});
            break :blk error.ExpectedWorldEnd;
        };
    }
};

const Background = union(enum) {
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

    fn fromXml(elem: *const xml.Element) !@This() {
        const typ = elem.queryAttribute("type", null) orelse return error.ExpectedBackgroundType;
        if (std.mem.eql(u8, typ, "single_color")) {
            return .{
                .single_color = .{
                    .color = try .fromStr(elem.queryAttribute("color", null)),
                },
            };
        } else if (std.mem.eql(u8, typ, "4_colors")) {
            return .{
                .four_colors = .{
                    .tl = try .fromStr(elem.queryAttribute("tl", null)),
                    .tr = try .fromStr(elem.queryAttribute("tr", null)),
                    .bl = try .fromStr(elem.queryAttribute("bl", null)),
                    .br = try .fromStr(elem.queryAttribute("br", null)),
                },
            };
        } else {
            background_log.err("expected one of ['single_color', '4_colors'], found {s}", .{typ});
            return error.InvalidBackgroundType;
        }
    }
};

const Pixel = struct {
    pos: UnsignedPoint(2),
    color: Color,
};

fn bilerp(
    tl: Pixel,
    tr: Pixel,
    bl: Pixel,
    br: Pixel,
    pos: UnsignedPoint(2),
) Color {
    const horizontal_factor = factor(@floatFromInt(tl.pos[0]), @floatFromInt(tr.pos[0]), @floatFromInt(pos[0]));
    const vertical_factor = factor(@floatFromInt(tl.pos[1]), @floatFromInt(bl.pos[1]), @floatFromInt(pos[1]));
    const top = tl.color.lerp(tr.color, horizontal_factor);
    const bot = bl.color.lerp(br.color, horizontal_factor);
    return top.lerp(bot, vertical_factor);
}

fn factor(x1: f64, x2: f64, x: f64) f64 {
    return std.math.clamp((x - x1) / (x2 - x1), 0, 1);
}

const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,

    // TODO: Add support for hexadecimal values.
    fn fromStr(str: ?[]const u8) !@This() {
        if (str == null or str.?.len == 0) return .{};
        const arr = try xml.parseUnsignedArray(u8, 3, str.?);
        return .{ .r = arr[0], .g = arr[1], .b = arr[2] };
    }

    fn interpolate(x: u8, y: u8, f: f64) u8 {
        if (f > 1 or f < 0) std.debug.panic(
            "lerp: the blend factor in lerp cannot be outside [0,1] range, found {any}",
            .{f},
        );
        return @as(u8, @intFromFloat((1.0 - f) * @as(f64, @floatFromInt(x)) + f * @as(f64, @floatFromInt(y))));
    }

    fn lerp(self: @This(), other: @This(), f: f64) @This() {
        return @This(){
            .r = interpolate(self.r, other.r, f),
            .g = interpolate(self.g, other.g, f),
            .b = interpolate(self.b, other.b, f),
        };
    }
};

/// Represents a element of a vector space of unsigned points.
pub fn UnsignedPoint(N: comptime_int) type {
    return @Vector(N, usize);
}

/// Represents a element of a vector space of signed points.
pub fn SignedPoint(N: comptime_int) type {
    return @Vector(N, isize);
}
