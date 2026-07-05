const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Color = @import("Color.zig");
const Camera = @import("Camera.zig").Camera;
const Film = @import("Film.zig");
const Integrator = @import("integrator.zig").Integrator;
const LookAt = @import("Look.zig");
const World = @import("World.zig");

const Scene = @This();

camera: Camera = .{ .rectangular = .{ .perspective = .{} } },
lookat: LookAt = .{},
integrator: Integrator = .flat,
film: Film = .{},

pub fn render(
    self: *Scene,
    gpa: Allocator,
    io: Io,
    dir: Io.Dir,
    world: *const World,
) !void {
    const buf = try gpa.alloc(Color, self.film.width * self.film.height);
    defer gpa.free(buf);

    const start = Io.Clock.awake.now(io);

    try self.integrator.render(
        io,
        buf,
        world,
        &self.camera,
        &self.lookat.normalFrame(),
        self.film.height,
        self.film.width,
    );

    const elapsed: f64 = @floatFromInt(start.untilNow(io, .awake).nanoseconds);
    std.log.info("elapsed time: {d:.2}s", .{elapsed / std.time.ns_per_s});

    return self.film.intoImg(gpa, io, dir, buf);
}
