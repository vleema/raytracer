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

/// Represents the digital world that the raytracer will be rendering.
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

/// Renders the described scene to the specified file.
pub fn renderImg(self: *Scene, gpa: Allocator, io: Io, dir: Io.Dir) !void {
    var allocating_writer = Io.Writer.Allocating.init(gpa);
    defer allocating_writer.deinit();

    try allocating_writer.ensureTotalCapacity(self.film.width * self.film.height * @sizeOf(Color));
    const writer = &allocating_writer.writer;

    try self.integrator.render(
        writer,
        &self.world,
        &self.camera,
        &self.look.normalFrame(),
        self.film.width,
        self.film.height,
    );

    const buf = allocating_writer.written();
    self.film.buf = std.mem.bytesAsSlice(Color, buf);
    return self.film.intoImgFile(gpa, io, dir);
}

/// Deinitializes allocated memory by the Scene.
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
