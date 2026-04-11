const std = @import("std");
const xml = @import("xml");

typ: enum { image } = .image,
width: u32 = 400,
height: u32 = 200,
filename: []const u8 = "out.ppm",
img_type: enum { ppm, png } = .ppm,

const film_log = std.log.scoped(.film);
var filename_buf: [256]u8 = undefined;

pub fn fromXml(elem: *const xml.Element) !@This() {
    var film = @This(){};

    if (elem.queryAttribute("type", null)) |typ| {
        if (std.mem.eql(u8, "image", typ))
            film.typ = .image
        else
            return error.InvalidFilmType;
    }

    if (elem.queryAttribute("width", null)) |x|
        film.width = try std.fmt.parseUnsigned(u32, x, 10);

    if (elem.queryAttribute("height", null)) |y|
        film.height = try std.fmt.parseUnsigned(u32, y, 10);

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
