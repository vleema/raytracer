const xml = @import("xml");

const std = @import("std");
const math = std.math;

const vec = @import("vec");
const Real = vec.Real;

const Frame = @import("Look.zig").Frame;
const Film = @import("Film.zig");
const Ray = @import("Ray.zig");

const log = std.log.scoped(.camera);

pub const Camera = union(enum) {
    spherical: enum {
        equirectangular,
        equal_area,

        fn generateRay(
            self: *const @This(),
            img_x: f64,
            img_y: f64,
            width: f64,
            height: f64,
            frame: Frame,
        ) Ray {
            const phi = 2.0 * math.pi * img_x / width;
            return switch (self.*) {
                .equirectangular => blk: {
                    const theta = math.pi * img_y / height;
                    break :blk Ray{
                        .origin = frame.origin,
                        .direction = vec.sphericalDirection(@sin(theta), @cos(theta), phi),
                    };
                },
                .equal_area => blk: {
                    const cos_theta = 1.0 - 2.0 * img_y / height;
                    const sin_theta = @sqrt(1.0 - cos_theta * cos_theta);
                    break :blk Ray{
                        .origin = frame.origin,
                        .direction = vec.sphericalDirection(sin_theta, cos_theta, phi),
                    };
                },
            };
        }
    },
    rectangular: union(enum) {
        orthographic: ScreenWindow,
        perspective: struct {
            fovy: u32 = 30,
        },

        const ScreenWindow = struct {
            left: f64 = -5.3,
            right: f64 = 5.3,
            bottom: f64 = -4,
            top: f64 = 4,
        };

        fn generateRay(
            self: *const @This(),
            img_x: f64,
            img_y: f64,
            width: f64,
            height: f64,
            frame: Frame,
        ) Ray {
            const aspect_ratio = width / height;
            const sw = self.screenWindow(aspect_ratio);
            const sw_x: Real(3) = @splat(sw.left + (sw.right - sw.left) * img_x / width);
            const sw_y: Real(3) = @splat(sw.bottom + (sw.top - sw.bottom) * img_y / height);

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
    },

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

        return switch (self.*) {
            .rectangular => |r| r.generateRay(ix, iy, w, h, frame),
            .spherical => |s| s.generateRay(ix, iy, w, h, frame),
        };
    }

    pub fn fromXml(elem: *const xml.Element) !@This() {
        const eql = std.mem.eql;
        const typ = elem.queryAttribute("type", null) orelse
            return error.ExpectedCameranType;

        if (eql(u8, typ, "orthographic")) {
            var cam: @This() = .{ .rectangular = .{ .orthographic = .{} } };
            const sw_val = elem.queryAttribute("screen_window", null) orelse return cam;
            const sw = try xml.parseFloatArray(f64, 4, sw_val);
            cam.rectangular.orthographic = .{ .left = sw[0], .right = sw[1], .bottom = sw[2], .top = sw[3] };
            return cam;
        }
        if (eql(u8, typ, "perspective")) {
            var cam: @This() = .{ .rectangular = .{ .perspective = .{} } };
            const fovy = elem.queryAttribute("fovy", null) orelse return cam;
            cam.rectangular.perspective.fovy = try std.fmt.parseUnsigned(u32, fovy, 10);
            return cam;
        }
        if (eql(u8, typ, "spherical")) {
            const variant = elem.queryAttribute("variant", null) orelse return error.ExpectedSphericalVariant;
            if (eql(u8, variant, "equirectangular")) {
                return .{ .spherical = .equirectangular };
            }
            if (eql(u8, variant, "equal_area")) {
                return .{ .spherical = .equal_area };
            }
            log.err("expected one of ['equirectangular', 'equal_area'], found {s}", .{variant});
            return error.InvalidSphericalVariant;
        }
        log.err("expected one of ['perspective', 'orthographic', 'spherical'], found {s}", .{typ});
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
    const cam: Camera = .{
        .rectangular = .{
            .orthographic = .{ .left = -2, .right = 2, .bottom = -2, .top = 2 },
        },
    };
    const film = Film{ .width = 4, .height = 4 };
    const ray = cam.generateRay(0, 0, axis_frame, film);
    try testing.expectEqual(Ray{ .origin = .{ -2, -2, 0 }, .direction = .{ 0, 0, 1 } }, ray);
}

test "orthographic: center pixel maps to screen window center" {
    const cam: Camera = .{
        .rectangular = .{
            .orthographic = .{ .left = -2, .right = 2, .bottom = -2, .top = 2 },
        },
    };
    const film = Film{ .width = 4, .height = 4 };
    const ray = cam.generateRay(2, 2, axis_frame, film);
    try testing.expectEqual(Ray{ .origin = .{ 0, 0, 0 }, .direction = .{ 0, 0, 1 } }, ray);
}

test "orthographic: direction is always frame direction" {
    const cam: Camera = .{ .rectangular = .{ .orthographic = .{} } };
    const film = Film{ .width = 4, .height = 4 };
    const ray = cam.generateRay(3, 1, axis_frame, film);
    try testing.expectEqual(@as(@Vector(3, f64), .{ 0, 0, 1 }), ray.direction);
}

test "perspective: origin is always frame origin" {
    const cam: Camera = .{ .rectangular = .{ .perspective = .{} } };
    const film = Film{ .width = 4, .height = 4 };
    const ray = cam.generateRay(1, 3, axis_frame, film);
    try testing.expectEqual(@as(@Vector(3, f64), .{ 0, 0, 0 }), ray.origin);
}

test "perspective: center pixel direction equals frame direction" {
    const cam: Camera = .{ .rectangular = .{ .perspective = .{} } };
    const film = Film{ .width = 4, .height = 4 };
    const ray = cam.generateRay(2, 2, axis_frame, film);
    try testing.expectEqual(@as(@Vector(3, f64), .{ 0, 0, 1 }), ray.direction);
}

test "spherical: origin is always frame origin" {
    const film = Film{ .width = 4, .height = 4 };
    const eq = Camera{ .spherical = .equirectangular };
    const ea = Camera{ .spherical = .equal_area };
    try testing.expectEqual(@as(@Vector(3, f64), .{ 0, 0, 0 }), eq.generateRay(2, 1, axis_frame, film).origin);
    try testing.expectEqual(@as(@Vector(3, f64), .{ 0, 0, 0 }), ea.generateRay(2, 1, axis_frame, film).origin);
}

test "equirectangular: top row maps to north pole" {
    const cam: Camera = .{ .spherical = .equirectangular };
    const film = Film{ .width = 4, .height = 4 };
    // theta = pi * 0/4 = 0 -> sin=0, cos=1 -> {0, 0, 1} for any phi.
    const ray = cam.generateRay(2, 0, axis_frame, film);
    try testing.expectEqual(@as(@Vector(3, f64), .{ 0, 0, 1 }), ray.direction);
}

test "equal_area: top row maps to north pole" {
    const cam: Camera = .{ .spherical = .equal_area };
    const film = Film{ .width = 4, .height = 4 };
    // cos_theta = 1 - 2*0/4 = 1, sin_theta = 0 -> {0, 0, 1} for any phi.
    const ray = cam.generateRay(2, 0, axis_frame, film);
    try testing.expectEqual(@as(@Vector(3, f64), .{ 0, 0, 1 }), ray.direction);
}

test "equal_area: bottom row maps to south pole" {
    const cam: Camera = .{ .spherical = .equal_area };
    const film = Film{ .width = 4, .height = 4 };
    // cos_theta = 1 - 2*4/4 = -1, sin_theta = 0 -> {0, 0, -1} for any phi
    const ray = cam.generateRay(2, 4, axis_frame, film);
    try testing.expectEqual(@as(@Vector(3, f64), .{ 0, 0, -1 }), ray.direction);
}
