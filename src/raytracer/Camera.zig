const std = @import("std");
const math = std.math;
const testing = std.testing;

const vec = @import("vec");
const Real = vec.Real;
const Film = @import("Film.zig");
const Frame = @import("Look.zig").Frame;
const Ray = @import("Ray.zig");

pub const Camera = union(enum) {
    spherical: Spherical,
    rectangular: Rectangular,

    pub fn preprocess(self: *const Camera, width: u32, height: u32) void {
        const w: f32 = @floatFromInt(width);
        const h: f32 = @floatFromInt(height);

        return switch (self.*) {
            .rectangular => |r| r.preprocesss(w, h),
            .spherical => {},
        };
    }

    /// Generates a ray coming out of the `Camera`.
    ///
    /// Returns the generated ray.
    pub fn generateRay(
        self: *const @This(),
        img_x: u32,
        img_y: u32,
        width: u32,
        height: u32,
        frame: *const Frame,
    ) Ray {
        const w: f32 = @floatFromInt(width);
        const h: f32 = @floatFromInt(height);
        const ix: f32 = @floatFromInt(img_x);
        const iy: f32 = @floatFromInt(img_y);

        return switch (self.*) {
            .rectangular => |r| r.generateRay(ix, iy, w, h, frame),
            .spherical => |s| s.generateRay(ix, iy, w, h, frame),
        };
    }
};

const Rectangular = union(enum) {
    orthographic: ScreenWindow,
    perspective: struct {
        fovy: u32 = 30,
    },

    const ScreenWindow = struct {
        left: f32 = -5.3,
        right: f32 = 5.3,
        bottom: f32 = -4,
        top: f32 = 4,
    };

    // SAFETY: Screen window is calculated only one time at the pre-process function, synchronously.
    var sw: ScreenWindow = undefined;

    fn preprocesss(self: *const Rectangular, width: f32, height: f32) void {
        const ar = width / height;
        sw = self.screenWindow(ar);
    }

    fn generateRay(
        self: *const @This(),
        img_x: f32,
        img_y: f32,
        width: f32,
        height: f32,
        frame: *const Frame,
    ) Ray {
        const sw_x: Real(3) = @splat(sw.left + (sw.right - sw.left) * img_x / width);
        const sw_y: Real(3) = @splat(sw.top + (sw.bottom - sw.top) * img_y / height);

        return switch (self.*) {
            .orthographic => Ray{
                .origin = frame.origin + sw_x * frame.right + sw_y * frame.orientation,
                .direction = frame.direction,
            },
            .perspective => Ray{
                .origin = frame.origin,
                .direction = frame.direction + sw_x * frame.right + sw_y * frame.orientation,
            },
        };
    }

    fn screenWindow(self: *const @This(), aspect_ratio: f32) ScreenWindow {
        return switch (self.*) {
            .orthographic => |e| e,
            .perspective => |p| blk: {
                const h = @tan(math.degreesToRadians(@as(f32, @floatFromInt(p.fovy))) / 2.0);
                break :blk ScreenWindow{
                    .left = -aspect_ratio * h,
                    .right = aspect_ratio * h,
                    .top = h,
                    .bottom = -h,
                };
            },
        };
    }
};

const Spherical = enum {
    equirectangular,
    equal_area,

    fn generateRay(
        self: *const @This(),
        img_x: f32,
        img_y: f32,
        width: f32,
        height: f32,
        frame: *const Frame,
    ) Ray {
        return switch (self.*) {
            .equirectangular => blk: {
                const u: f32 = img_x / width;
                const v: f32 = img_y / height;
                const phi = 2.0 * math.pi * u;
                const theta = math.pi * v;
                break :blk Ray{
                    .origin = frame.origin,
                    .direction = vec.sphericalDirection(@sin(theta), @cos(theta), phi),
                };
            },
            .equal_area => blk: {
                const u = 2.0 * (img_x / width) - 1;
                const v = 2.0 * (img_y / height) - 1;
                const up = @abs(u);
                const vp = @abs(v);
                const signed_dist = 1 - (up + vp);
                const dist = @abs(signed_dist);
                const r = 1 - dist;
                const phi = if (r == 0) 1 else ((vp - up) / r + 1) * math.pi / 4;
                const z = math.copysign(1 - r * r, signed_dist);
                const cos_phi = math.copysign(@cos(phi), u);
                const sin_phi = math.copysign(@sin(phi), v);
                break :blk Ray{
                    .origin = frame.origin,
                    .direction = .{ cos_phi * r * @sqrt(2 - r * r), sin_phi * r * @sqrt(2 - r * r), z },
                };
            },
        };
    }
};

const axis_frame = Frame{
    .origin = .{ 0, 0, 0 },
    .direction = .{ 0, 0, 1 },
    .right = .{ 1, 0, 0 },
    .orientation = .{ 0, 1, 0 },
};

test "orthographic: top-left pixel maps to screen window corner" {
    const cam: Camera = .{
        .rectangular = .{
            .orthographic = .{ .left = -2, .right = 2, .bottom = -2, .top = 2 },
        },
    };
    const film = Film{ .width = 4, .height = 4 };
    cam.preprocess(film.width, film.height);
    const ray = cam.generateRay(0, 0, film.width, film.height, &axis_frame);
    try testing.expectEqual(Ray{ .origin = .{ -2, 2, 0 }, .direction = .{ 0, 0, 1 } }, ray);
}

test "orthographic: center pixel maps to screen window center" {
    const cam: Camera = .{
        .rectangular = .{
            .orthographic = .{ .left = -2, .right = 2, .bottom = -2, .top = 2 },
        },
    };
    const film = Film{ .width = 4, .height = 4 };
    cam.preprocess(film.width, film.height);
    const ray = cam.generateRay(2, 2, film.width, film.height, &axis_frame);
    try testing.expectEqual(Ray{ .origin = .{ 0, 0, 0 }, .direction = .{ 0, 0, 1 } }, ray);
}

test "orthographic: direction is always frame direction" {
    const cam: Camera = .{ .rectangular = .{ .orthographic = .{} } };
    const film = Film{ .width = 4, .height = 4 };
    cam.preprocess(film.width, film.height);
    const ray = cam.generateRay(3, 1, film.width, film.height, &axis_frame);
    try testing.expectEqual(@as(@Vector(3, f32), .{ 0, 0, 1 }), ray.direction);
}

test "perspective: origin is always frame origin" {
    const cam: Camera = .{ .rectangular = .{ .perspective = .{} } };
    const film = Film{ .width = 4, .height = 4 };
    cam.preprocess(film.width, film.height);
    const ray = cam.generateRay(1, 3, film.width, film.height, &axis_frame);
    try testing.expectEqual(@as(@Vector(3, f32), .{ 0, 0, 0 }), ray.origin);
}

test "perspective: center pixel direction equals frame direction" {
    const cam: Camera = .{ .rectangular = .{ .perspective = .{} } };
    const film = Film{ .width = 4, .height = 4 };
    cam.preprocess(film.width, film.height);
    const ray = cam.generateRay(2, 2, film.width, film.height, &axis_frame);
    try testing.expectEqual(@as(@Vector(3, f32), .{ 0, 0, 1 }), ray.direction);
}

test "spherical: origin is always frame origin" {
    const film = Film{ .width = 4, .height = 4 };
    const eq = Camera{ .spherical = .equirectangular };
    const ea = Camera{ .spherical = .equal_area };
    try testing.expectEqual(@as(@Vector(3, f32), .{ 0, 0, 0 }), eq.generateRay(2, 1, film.width, film.height, &axis_frame).origin);
    try testing.expectEqual(@as(@Vector(3, f32), .{ 0, 0, 0 }), ea.generateRay(2, 1, film.width, film.height, &axis_frame).origin);
}

test "equirectangular: top row maps to north pole" {
    const cam: Camera = .{ .spherical = .equirectangular };
    const film = Film{ .width = 4, .height = 4 };
    const ray = cam.generateRay(2, 0, film.width, film.height, &axis_frame);
    try testing.expectEqual(@as(@Vector(3, f32), .{ 0, 0, 1 }), ray.direction);
}
