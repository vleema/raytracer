const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const xml = @import("xml");

const Camera = @import("Camera.zig").Camera;
const Color = @import("img.zig").Color;
const Frame = @import("Look.zig").Frame;
const World = @import("World.zig");

const log = std.log.scoped(.integrator);

pub const Integrator = union(enum) {
    flat: Flat,

    pub fn render(
        self: *const Integrator,
        buf: []Color,
        world: *const World,
        camera: *const Camera,
        frame: *const Frame,
        width: u32,
        height: u32,
    ) !void {
        return switch (self.*) {
            .flat => Flat.render(buf, world, camera, frame, width, height),
        };
    }

    pub fn fromXml(elem: *const xml.Element) !@This() {
        const typ = elem.queryAttribute("type", null) orelse
            return error.ExpectedIntegratorType;

        if (std.mem.eql(u8, typ, "flat")) {
            return .flat;
        }
        log.err("expected one of ['flat'], found {s}", .{typ});
        return error.InvalidIntegratorType;
    }
};

pub const Flat = struct {
    pub fn render(
        buf: []Color,
        world: *const World,
        camera: *const Camera,
        frame: *const Frame,
        width: u32,
        height: u32,
    ) !void {
        for (0..height) |y| {
            for (0..width) |x| {
                const ray = camera.generateRay(@intCast(x), @intCast(y), width, height, frame);
                const color = if (world.objHit(&ray)) |v|
                    v.material.color
                else
                    world.background.ptColor(
                        width,
                        height,
                        .{ @floatFromInt(x), @floatFromInt(y) },
                    );

                buf[x + y * width] = color;
            }
        }
    }
};
