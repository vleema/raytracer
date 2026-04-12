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

camera: Camera = .{ .rectangular = .{ .perspective = .{} } },
look: Look = .{},
integrator: Integrator = .flat,
film: Film = .{},
world: World = .{},

const log = std.log.scoped(.scene);

/// Creates a scene from a xml file.
pub fn fromXmlFile(allocator: std.mem.Allocator, file: std.fs.File) !Scene {
    const md = try file.stat();
    const mmap = try std.posix.mmap(null, md.size, std.posix.PROT.READ, .{ .TYPE = .PRIVATE }, file.handle, 0);
    defer std.posix.munmap(mmap);

    var root = try xml.parse(mmap, allocator);
    defer root.deinit(allocator);

    return fromXml(allocator, &root);
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
pub fn fromXml(allocator: std.mem.Allocator, root: *const xml.Element) !@This() {
    var scene = @This(){};
    const options = .{
        .camera = &scene.camera,
        .lookat = &scene.look,
        .integrator = &scene.integrator,
        .film = &scene.film,
        .world = &scene.world,
    };
    if (try xml.parseChildren(allocator, options, root)) |unknown| {
        const keys_str = comptime xml.fieldKeysStr(@TypeOf(options));
        log.err("unrecognized option '{s}', expected one of {s}", .{ unknown, keys_str });
        return error.UnrecognizedOption;
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
    std.debug.print("ray: {}\n", .{self.camera.generateRay(x, y, self.look.normalFrame(), self.film)});
    return .{ color.r, color.g, color.b };
}

pub fn deinit(self: *Scene, allocator: std.mem.Allocator) void {
    self.world.deinit(allocator);
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
            .rectangular = .{
                .orthographic = .{
                    .left = -5.3,
                    .right = 5.3,
                    .bottom = -4,
                    .top = 4,
                },
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
    var actual = try Scene.fromXml(std.testing.allocator, &root);
    defer actual.deinit(std.testing.allocator);
    try std.testing.expectEqualDeep(expected, actual);
}
