const std = @import("std");
const xml = @import("xml");
const png = @import("png");
const ppm = @import("ppm");

const img = @import("img.zig");
const Ray = img.Ray;
const Color = img.Color;

const Camera = @import("Camera.zig").Camera;
const Film = @import("Film.zig");
const Integrator = @import("Integrator.zig").Integrator;
const Look = @import("Look.zig");
const World = @import("World.zig");

const Scene = @This();

camera: Camera = .{ .perspective = .{} },
look: Look = .{},
integrator: Integrator = .flat,
film: Film = .{},
world: World = .{},

/// Creates a scene from a xml file.
pub fn fromXmlFile(file: std.fs.File) !Scene {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const md = try file.stat();
    const mmap = try std.posix.mmap(null, md.size, std.posix.PROT.READ, .{ .TYPE = .PRIVATE }, file.handle, 0);
    defer std.posix.munmap(mmap);
    const root = try xml.parse(mmap, arena_allocator);

    return fromXml(&root);
}

/// Writes the scene into a file under `dir`.
pub fn intoImgFile(self: *const Scene, allocator: std.mem.Allocator, dir: std.fs.Dir) !void {
    var out = try dir.createFile(self.film.filename, .{});
    defer out.close();

    switch (self.film.img_type) {
        .png => try png.writeTrueColor8(allocator, &out, self.film.width, self.film.height, self),
        .ppm => try ppm.writeP6(&out, self.film.width, self.film.height, self),
    }
}

/// Creates a scene from a `xml.Element`.
pub fn fromXml(root: *const xml.Element) !@This() {
    var scene = @This(){};
    var node = root.values.first;
    while (node) |n| {
        const eql = std.mem.eql;
        const elem: *xml.Element = @fieldParentPtr("node", n);
        node = n.next;

        // TODO: improve option parsing.
        if (eql(u8, elem.key, "camera")) {
            scene.camera = try .fromXml(elem);
        } else if (eql(u8, elem.key, "lookat")) {
            scene.look = try .fromXml(elem);
        } else if (eql(u8, elem.key, "integrator")) {
            scene.integrator = try .fromXml(elem);
        } else if (eql(u8, elem.key, "film")) {
            scene.film = try .fromXml(elem);
        } else if (eql(u8, elem.key, "world")) {
            scene.world = try .fromXml(elem);
        } else {
            std.log.err("unrecognized option {s}", .{elem.key});
            return error.UnrecognizedOption;
        }
    }
    return scene;
}

/// Returns the array form of color of a given pixel in a image file.
pub fn render(self: *const @This(), x: u32, y: u32) [3]u8 {
    const color = self.world.background.ptColor(
        self.film.width,
        self.film.height,
        .{ @floatFromInt(x), @floatFromInt(y) },
    );
    std.debug.print("ray: {}\n", .{self.camera.generateRay(x, y, self.look.frame(), self.film)});
    return .{ color.r, color.g, color.b };
}

test "from xml" {
    const str =
        \\<RT3>
        \\    <lookat look_from="0 0 -7" look_at="0 0 0" up="0 1 0" />
        \\    <camera type="orthographic" screen_window="-5.3 5.3 -4 4"/>
        \\    <integrator type="flat" />
        \\    <film type="image" width="200" height="100" filename="simple_bkg.png" img_type="png" />
        \\    <world>
        \\        <background type="single_color" color="153 204 255"/>
        \\    </world>
        \\</RT3>
    ;
    const expected = Scene{
        .camera = .{
            .orthographic = .{
                .left = -5.3,
                .right = 5.3,
                .bottom = -4,
                .top = 4,
            },
        },
        .look = .{
            .from = .{ 0, 0, -7 },
            .at = .{ 0, 0, 0 },
            .up = .{ 0, 1, 0 },
        },
        .integrator = .flat,
        .film = .{
            .typ = .image,
            .width = 200,
            .height = 100,
            .filename = "simple_bkg.png",
            .img_type = .png,
        },
        .world = .{
            .background = .{
                .single_color = .{
                    .color = .{
                        .r = 153,
                        .g = 204,
                        .b = 255,
                    },
                },
            },
        },
    };
    var root = try xml.parse(str, std.testing.allocator);
    defer root.deinit(std.testing.allocator);
    const actual = try Scene.fromXml(&root);
    try std.testing.expectEqualDeep(expected, actual);
}
