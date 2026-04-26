const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const xml = @import("xml");
const png = @import("png");
const ppm = @import("ppm");
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
pub fn fromXmlFile(gpa: Allocator, io: Io, file: Io.File) !Scene {
    const md = try file.stat(io);
    const mmap = try std.posix.mmap(null, md.size, .{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0);
    defer std.posix.munmap(mmap);

    var root = try xml.parse(mmap, gpa);
    defer root.deinit(gpa);

    return fromXml(gpa, &root);
}

/// Writes the scene into a file under `dir`.
pub fn intoImgFile(self: *const Scene, gpa: Allocator, io: Io, dir: Io.Dir) !void {
    var out = try dir.createFile(io, self.film.filename, .{});
    defer out.close(io);

    switch (self.film.img_type) {
        .png => try png.writeTrueColor8(self, gpa, io, out, self.film.width, self.film.height),
        .ppm => try ppm.writeP6(self, io, out, self.film.width, self.film.height),
    }
}

/// Creates a scene from a `xml.Element`.
pub fn fromXml(gpa: Allocator, root: *const xml.Element) !@This() {
    var scene = @This(){};
    errdefer scene.deinit(gpa);
    const options = .{
        .camera = &scene.camera,
        .lookat = &scene.look,
        .integrator = &scene.integrator,
        .film = &scene.film,
        .world = &scene.world,
    };
    if (try xml.parseChildren(gpa, options, root)) |unknown| {
        const keys_str = comptime xml.fieldKeysStr(@TypeOf(options));
        log.err("unrecognized option '{s}', expected one of {s}", .{ unknown, keys_str });
        return error.UnrecognizedOption;
    }
    return scene;
}

/// Returns the array form of color of a given pixel in a image file.
pub fn render(self: *const Scene, x: u32, y: u32) [3]u8 {
    const ray = self.camera.generateRay(x, y, self.look.normalFrame(), self.film);
    const color = if (self.world.intersect(&ray)) |c|
        c
    else
        self.world.background.ptColor(
            self.film.width,
            self.film.height,
            .{ @floatFromInt(x), @floatFromInt(y) },
        );
    return .{ color.r, color.g, color.b };
}

pub fn deinit(self: *Scene, allocator: Allocator) void {
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
            .materials = .{ .list = .empty },
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
