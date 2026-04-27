const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const png = @import("png");
const ppm = @import("ppm");
const xml = @import("xml");

const img = @import("img.zig");
const Color = img.Color;
const Camera = @import("Camera.zig").Camera;
const Film = @import("Film.zig");
const Integrator = @import("Integrator.zig").Integrator;
const Look = @import("Look.zig");
const World = @import("World.zig");

const Scene = @This();

/// Represents the camera object inside the raytracer Scene.
camera: Camera = .{ .rectangular = .{ .perspective = .{} } },

/// Represents the look from the camera inside the raytracer Scene.
look: Look = .{},

/// Represents a integrator object, responsible for calculating the amount of light arriving at a given pixel.
integrator: Integrator = .flat,

/// Represents the result image metadata and buffer.
film: Film = .{},

const log = std.log.scoped(.scene);

/// Creates a scene from a `xml.Element`.
pub fn fromXml(gpa: Allocator, root: *const xml.Element) !Scene {
    var scene: Scene = .{};
    const options = .{
        .camera = &scene.camera,
        .lookat = &scene.look,
        .integrator = &scene.integrator,
        .film = &scene.film,
    };
    if (try xml.parseElemValues(gpa, options, root)) |unknowns| {
        const keys_str = comptime xml.fieldKeysStr(@TypeOf(options));
        for (unknowns.items) |u| {
            log.err("unrecognized option '{s}', expected one of {s}", .{ u, keys_str });
        }
        return error.UnrecognizedOption;
    }
    return scene;
}

/// Renders the scene using the integrator into the file described by `Film`.
pub fn render(
    self: *Scene,
    gpa: Allocator,
    io: Io,
    dir: Io.Dir,
    world: *const World,
) !void {
    const buf = try gpa.alloc(Color, self.film.width * self.film.height);
    defer gpa.free(buf);

    try self.integrator.render(
        buf,
        world,
        &self.camera,
        &self.look.normalFrame(),
        self.film.width,
        self.film.height,
    );

    return self.film.intoImg(gpa, io, dir, buf);
}

test "from xml" {
    const str =
        \\<scene>
        \\    <lookat look_from="0 0 -7" look_at="0 0 0" up="0 1 0" />
        \\    <camera type="orthographic" screen_window="-5.3 5.3 -4 4"/>
        \\    <integrator type="flat" />
        \\    <film type="image" width="200" height="100" filename="simple_bkg.png" img_type="png" />
        \\</scene>
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
    };
    var root = try xml.parse(str, std.testing.allocator);
    defer root.deinit(std.testing.allocator);

    const actual = try Scene.fromXml(std.testing.allocator, &root);

    try std.testing.expectEqualDeep(expected, actual);
}
