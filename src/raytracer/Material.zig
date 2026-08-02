const std = @import("std");
const Allocator = std.mem.Allocator;
const MultiArrayList = std.MultiArrayList;
const ArrayList = std.ArrayList;
const vec = @import("vec");

const Color = @import("Color.zig");
const Light = @import("Light.zig");

const Material = @This();

tag: Tag,
name: []const u8 = "default",
extra_idx: u32 = 0,

pub const Tag = enum {
    flat,
    blinn,
};

pub const List = struct {
    list: MultiArrayList(Material) = .empty,
    blinn: ArrayList(Blinn) = .empty,
    flat: ArrayList(Flat) = .empty,

    pub fn deinit(self: *List, gpa: Allocator) void {
        for (self.list.items(.name)) |n| gpa.free(n);
        self.list.deinit(gpa);
        self.blinn.deinit(gpa);
        self.flat.deinit(gpa);
    }

    pub fn find(self: *const Material.List, name: []const u8) ?usize {
        const names = self.list.items(.name);
        return for (names, 0..) |n, i| {
            if (std.mem.eql(u8, name, n)) break i;
        } else null;
    }

    pub fn fromRaw(gpa: Allocator, raw: []const Material.Raw) !@This() {
        var this = @This(){};
        errdefer this.deinit(gpa);
        try this.list.ensureUnusedCapacity(gpa, raw.len);
        for (raw) |r| try this.appendRawAssumeCapacity(gpa, r);
        return this;
    }

    fn appendRawAssumeCapacity(self: *@This(), gpa: Allocator, raw: Material.Raw) !void {
        const names = self.list.items(.name);
        for (names) |name| {
            if (std.mem.eql(u8, name, raw.name)) {
                std.log.err("duplicate material '{s}'", .{name});
                return error.DuplicateMaterial;
            }
        }
        var mat: Material = .{ .tag = raw.inner, .name = raw.name };
        switch (raw.inner) {
            .flat => |f| {
                mat.extra_idx = @intCast(self.flat.items.len);
                try self.flat.append(gpa, try .fromRaw(f));
            },
            .blinn => |b| {
                mat.extra_idx = @intCast(self.blinn.items.len);
                try self.blinn.append(gpa, b);
            },
        }
        self.list.appendAssumeCapacity(mat);
    }
};

pub const Flat = struct {
    color: Color = .{},

    pub const Raw = struct {
        color: Color.Raw = .{ .hex = "#ff0000" },
    };

    pub fn fromRaw(r: Flat.Raw) !Flat {
        return .{ .color = try .fromRaw(r.color) };
    }
};

pub const Blinn = struct {
    ambient: [3]f32,
    diffuse: [3]f32,
    specular: [3]f32,
    mirror: [3]f32,
    glossiness: f32,

    pub fn attenuate(
        self: *const Blinn,
        attenuation: Light.Common.Attenuation,
        dist: f32,
    ) @This() {
        const val = attenuation.val(dist);
        return .{
            .ambient = vec.mul_scalar(3, f32, val, self.ambient),
            .diffuse = vec.mul_scalar(3, f32, val, self.diffuse),
            .specular = vec.mul_scalar(3, f32, val, self.specular),
            .mirror = self.mirror,
            .glossiness = self.glossiness,
        };
    }
};

pub const Raw = struct {
    name: []const u8,
    inner: union(Tag) {
        flat: Flat.Raw,
        blinn: Blinn,
    },

    pub fn intoInternal(self: @This()) !Material {
        return .{
            .tag = self.inner,
            .name = self.name,
        };
    }
};
