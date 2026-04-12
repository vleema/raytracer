const std = @import("std");
const eql = std.mem.eql;
const xml = @import("xml");

typ: enum { image } = .image,
width: u32 = 400,
height: u32 = 200,
filename: []const u8 = "out.ppm",
img_type: enum { ppm, png } = .ppm,

const log = std.log.scoped(.film);
var filename_buf: [256]u8 = undefined;

pub fn fromXml(elem: *const xml.Element) !@This() {
    var film = @This(){};
    var node = elem.attrs.first;
    // TODO: Improve this by implementing a meta-programming wrapper for xml options.
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
