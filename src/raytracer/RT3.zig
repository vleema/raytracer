const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;

const xml = @import("xml");

const Scene = @import("Scene.zig");
const World = @import("World.zig");

const RT3 = @This();

scenes: Scenes = .{},
world: World = .{},

/// Deallocates the memory allocated by `self`.
pub fn deinit(self: *RT3, gpa: Allocator) void {
    self.scenes.deinit(gpa);
    self.world.deinit(gpa);
}

/// Constructs the ray tracer from a xml file specification.
pub fn fromXmlFile(gpa: Allocator, io: Io, file: Io.File) !RT3 {
    const md = try file.stat(io);
    const mmap = try std.posix.mmap(null, md.size, .{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0);
    defer std.posix.munmap(mmap);

    var root = try xml.parse(mmap, gpa);
    defer root.deinit(gpa);

    return .fromXml(gpa, &root);
}

/// Constructs the ray tracer from a xml element.
pub fn fromXml(gpa: Allocator, root: *const xml.Element) !RT3 {
    var rt: RT3 = .{};
    errdefer rt.deinit(gpa);
    const options = .{
        .scene = &rt.scenes,
        .world = &rt.world,
    };
    if (try xml.parseElemValues(gpa, options, root)) |unknowns| {
        const keys_str = comptime xml.fieldKeysStr(@TypeOf(options));
        for (unknowns.items) |u| {
            std.log.err("unrecognized option '{s}', expected one of {s}", .{ u, keys_str });
        }
        return error.UnrecognizedOption;
    }
    return rt;
}

/// Render all the scenes defined by the ray tracer.
pub fn renderAll(self: *const RT3, gpa: Allocator, io: Io, dir: Io.Dir) !void {
    errdefer std.log.err("an error occured while rendering", .{});
    for (self.scenes.list.items) |*s| {
        try s.render(gpa, io, dir, &self.world);
    }
}

const Scenes = struct {
    list: ArrayList(Scene) = .empty,

    fn deinit(self: *Scenes, gpa: Allocator) void {
        self.list.deinit(gpa);
    }

    pub fn addFromXml(self: *Scenes, gpa: Allocator, elem: *const xml.Element) !void {
        try self.list.append(gpa, try .fromXml(gpa, elem));
    }
};
