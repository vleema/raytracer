const std = @import("std");
const Allocator = std.mem.Allocator;
const MultiArrayList = std.MultiArrayList;
const ArrayList = std.ArrayList;

const vec = @import("vec");

const Material = @import("Material.zig");

const Light = @This();

tag: Tag,
common: Common,

pub const Tag = enum {
    ambient,
    directional,
    point,
    spotlight,
};

pub const Common = struct {
    intensity: [3]f32,
    attenuation: Attenuation,
    extra_idx: u32 = 0,

    pub const Attenuation = struct {
        constant: f32,
        linear: f32,
        quadratic: f32,

        pub fn val(self: *const @This(), dist: f32) f32 {
            return 1.0 / (self.constant + self.linear *
                dist + self.quadratic * dist * dist);
        }
    };

    pub fn attenuate(
        self: *const @This(),
        material: *const Material.Blinn,
        dist: f32,
    ) Material.Blinn {
        const val = self.attenuation.val(dist);
        return .{
            .ambient = vec.mul_scalar(3, f32, val, material.ambient),
            .diffuse = vec.mul_scalar(3, f32, val, material.diffuse),
            .specular = vec.mul_scalar(3, f32, val, material.specular),
            .mirror = material.mirror,
            .glossiness = material.glossiness,
        };
    }
};

pub const List = struct {
    list: MultiArrayList(Light) = .empty,
    directional: ArrayList(Directional) = .empty,
    point: ArrayList(Point) = .empty,
    spotlight: ArrayList(Spotlight) = .empty,

    pub fn deinit(self: *List, gpa: Allocator) void {
        self.list.deinit(gpa);
        self.directional.deinit(gpa);
        self.point.deinit(gpa);
        self.spotlight.deinit(gpa);
    }

    pub fn fromRaw(gpa: Allocator, raw: []const Light.Raw) !List {
        var this: List = .{};
        errdefer this.deinit(gpa);
        try this.list.ensureUnusedCapacity(gpa, raw.len);
        for (raw) |r| try this.appendRawAssumeCapacity(gpa, r);
        return this;
    }

    fn appendRawAssumeCapacity(self: *List, gpa: Allocator, r: Light.Raw) !void {
        // SAFETY: `extra_idx` is defined by the switch below.
        var extra_idx: u32 = undefined;
        switch (r.inner) {
            .ambient => {},
            .directional => |d| {
                extra_idx = @intCast(self.directional.items.len);
                try self.directional.append(gpa, d);
            },
            .point => |p| {
                extra_idx = @intCast(self.point.items.len);
                try self.point.append(gpa, p);
            },
            .spotlight => |p| {
                var l = p;
                l.cutoff = @cos(vec.angleToRad(p.cutoff));
                l.falloff = @cos(vec.angleToRad(p.falloff));
                extra_idx = @intCast(self.spotlight.items.len);
                try self.spotlight.append(gpa, l);
            },
        }
        var item = try r.intoInternal();
        item.common.extra_idx = extra_idx;
        self.list.appendAssumeCapacity(item);
    }
};

pub const Ambient = struct {};

pub const Directional = struct {
    from: [3]f32,
    to: [3]f32,
};

pub const Point = struct {
    from: [3]f32,
};

pub const Spotlight = struct {
    from: [3]f32,
    to: [3]f32,
    cutoff: f32,
    falloff: f32,
};

pub const Variant = union(Tag) {
    ambient: Ambient,
    directional: Directional,
    point: Point,
    spotlight: Spotlight,
};

pub const Raw = struct {
    inner: Variant,
    scale: [3]f32 = .{ 1, 1, 1 },
    intensity: [3]f32 = .{ 1, 1, 1 },
    attenuation: Common.Attenuation = .{
        .constant = 1,
        .linear = 0.09,
        .quadratic = 0.032,
    },

    pub fn intoInternal(self: @This()) !Light {
        return .{
            .tag = self.inner,
            .common = .{
                .intensity = vec.mul(3, f32, .{ self.intensity, self.scale }),
                .attenuation = self.attenuation,
            },
        };
    }
};
