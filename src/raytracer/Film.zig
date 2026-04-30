const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const eql = std.mem.eql;

const png = @import("png");
const ppm = @import("ppm");
const xml = @import("xml");

const Color = @import("img.zig").Color;

const Film = @This();

/// The type of the film. In the future, it could support animations.
typ: enum { image } = .image,

/// The width of the generated film.
width: u32 = 400,

/// The height of the generated film.
height: u32 = 200,

/// The name of the generated film file.
filename: []const u8 = "out.png",

/// The type of image that will be generated.
img_type: enum { ppm, png } = .png,

/// The color buffer of the film, this is filled by the `Scene` in the `render` method
/// and it's used when converting the Film to a file.
buf: []const Color = &.{},

const log = std.log.scoped(.film);
var filename_buf: [256]u8 = undefined;

/// Creates a Film from xml `Element`.
pub fn fromXml(elem: *const xml.Element) !Film {
    var film = Film{};
    var node = elem.attrs.first;
    // TODO: Improve this by implementing a meta-programming wrapper for xml attributes.
    while (node) |n| : (node = n.next) {
        const attr: *const xml.Attribute = @fieldParentPtr("node", n);

        if (eql(u8, attr.key, "type")) {
            if (std.mem.eql(u8, "image", attr.value))
                film.typ = .image
            else {
                log.err(
                    "invalid film type, expected one of ['image'], found {s}",
                    .{attr.value},
                );
                return error.InvalidFilmType;
            }
        } else if (eql(u8, attr.key, "width")) {
            film.width = try std.fmt.parseUnsigned(u32, attr.value, 10);
        } else if (eql(u8, attr.key, "height")) {
            film.height = try std.fmt.parseUnsigned(u32, attr.value, 10);
        } else if (eql(u8, attr.key, "filename")) {
            std.mem.copyForwards(u8, &filename_buf, attr.value);
            film.filename = filename_buf[0..attr.value.len];
        } else if (eql(u8, attr.key, "img_type")) {
            if (std.mem.eql(u8, "ppm", attr.value)) {
                film.img_type = .ppm;
            } else if (std.mem.eql(u8, "png", attr.value)) {
                film.img_type = .png;
            } else {
                log.err("expected one of ['ppm', 'png'], found {s}", .{attr.value});
                return error.InvalidImgType;
            }
        } else {
            log.warn(
                "unknown option '{s}', expected one of ['width', 'height', 'filename', 'type', 'img_type']",
                .{attr.key},
            );
        }
    }

    return film;
}

/// Writes the contents of the color buffer to a image file.
pub fn intoImg(
    self: *Film,
    gpa: Allocator,
    io: Io,
    dir: Io.Dir,
    buf: []const Color,
) !void {
    self.buf = buf;

    var out = try dir.createFile(io, self.filename, .{});
    defer out.close(io);

    switch (self.img_type) {
        .png => try png.writeTrueColor8(self, gpa, io, out, self.width, self.height),
        .ppm => try ppm.writeP6(self, io, out, self.width, self.height),
    }
}

/// Gets a color for a given pixel in the color buffer.
pub fn color(self: *const Film, x: u32, y: u32) [3]u8 {
    const c = self.buf[x + y * self.width];
    return [_]u8{ c.r, c.g, c.b };
}
