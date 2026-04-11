const std = @import("std");
const xml = @import("xml");

const vec = @import("vec");
const Real = vec.Real;

const Frame = @import("Look.zig").Frame;
const Film = @import("Film.zig");
const Ray = @import("Ray.zig");

pub const Camera = union(enum) {
    perspective: struct {
        fovy: u32 = 30,
    },
    orthographic: ScreenWindow,

    const ScreenWindow = struct {
        left: f64 = -5.3,
        right: f64 = 5.3,
        bottom: f64 = -4,
        top: f64 = 4,
    };

    pub fn generateRay(
        self: *const @This(),
        img_x: u32,
        img_y: u32,
        frame: Frame,
        film: Film,
    ) Ray {
        const w: f64 = @floatFromInt(film.width);
        const h: f64 = @floatFromInt(film.height);
        const ix: f64 = @floatFromInt(img_x);
        const iy: f64 = @floatFromInt(img_y);

        const aspect_ratio = w / h;
        const sw = self.screenWindow(aspect_ratio);
        const sw_x: Real(3) = @splat(sw.left + (sw.right - sw.left) * ix / w);
        const sw_y: Real(3) = @splat(sw.bottom + (sw.top - sw.bottom) * iy / h);

        return switch (self.*) {
            .orthographic => |_| Ray{
                .origin = frame.origin + sw_x * frame.right + sw_y * frame.orientation,
                .direction = frame.direction,
            },
            .perspective => |_| Ray{
                .origin = frame.origin,
                .direction = frame.direction + sw_x * frame.right + sw_y * frame.orientation,
            },
        };
    }

    fn screenWindow(self: *const @This(), aspect_ratio: f64) ScreenWindow {
        return switch (self.*) {
            .orthographic => |e| e,
            .perspective => |p| blk: {
                const h = std.math.tan(@as(f64, @floatFromInt(p.fovy)) / 2.0);
                break :blk ScreenWindow{
                    .left = -aspect_ratio * h,
                    .right = aspect_ratio * h,
                    .top = h,
                    .bottom = -h,
                };
            },
        };
    }

    pub fn fromXml(elem: *const xml.Element) !@This() {
        if (elem.queryAttribute("type", "orthographic")) |_| {
            var cam: @This() = .{ .orthographic = .{} };
            const sw_val = elem.queryAttribute("screen_window", null) orelse return cam;
            const sw = try xml.parseFloatArray(f64, 4, sw_val);
            cam.orthographic = .{ .left = sw[0], .right = sw[1], .bottom = sw[2], .top = sw[3] };
            return cam;
        }
        if (elem.queryAttribute("type", "perspective")) |_| {
            var cam: @This() = .{ .perspective = .{} };
            const fovy = elem.queryAttribute("fovy", null) orelse return cam;
            cam.perspective.fovy = try std.fmt.parseUnsigned(u32, fovy, 10);
            return cam;
        }
        return error.InvalidCameraType;
    }
};

const testing = std.testing;

const axis_frame = Frame{
    .origin = .{ 0, 0, 0 },
    .direction = .{ 0, 0, 1 },
    .right = .{ 1, 0, 0 },
    .orientation = .{ 0, 1, 0 },
};

test "orthographic: top-left pixel maps to screen window corner" {
    const cam: Camera = .{ .orthographic = .{ .left = -2, .right = 2, .bottom = -2, .top = 2 } };
    const film = Film{ .width = 4, .height = 4 };
    const ray = cam.generateRay(0, 0, axis_frame, film);
    try testing.expectEqual(Ray{ .origin = .{ -2, -2, 0 }, .direction = .{ 0, 0, 1 } }, ray);
}

test "orthographic: center pixel maps to screen window center" {
    const cam: Camera = .{ .orthographic = .{ .left = -2, .right = 2, .bottom = -2, .top = 2 } };
    const film = Film{ .width = 4, .height = 4 };
    const ray = cam.generateRay(2, 2, axis_frame, film);
    try testing.expectEqual(Ray{ .origin = .{ 0, 0, 0 }, .direction = .{ 0, 0, 1 } }, ray);
}

test "orthographic: direction is always frame direction" {
    const cam: Camera = .{ .orthographic = .{} };
    const film = Film{ .width = 4, .height = 4 };
    const ray = cam.generateRay(3, 1, axis_frame, film);
    try testing.expectEqual(@as(@Vector(3, f64), .{ 0, 0, 1 }), ray.direction);
}

test "perspective: origin is always frame origin" {
    const cam: Camera = .{ .perspective = .{} };
    const film = Film{ .width = 4, .height = 4 };
    const ray = cam.generateRay(1, 3, axis_frame, film);
    try testing.expectEqual(@as(@Vector(3, f64), .{ 0, 0, 0 }), ray.origin);
}

test "perspective: center pixel direction equals frame direction" {
    const cam: Camera = .{ .perspective = .{} };
    const film = Film{ .width = 4, .height = 4 };
    const ray = cam.generateRay(2, 2, axis_frame, film);
    try testing.expectEqual(@as(@Vector(3, f64), .{ 0, 0, 1 }), ray.direction);
}
