const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const pre = @import("pre");

const Scene = @import("Scene.zig");
const World = @import("World.zig");

const Config = @This();

scene: Scene = .{},
world: World = .{},

pub const Raw = struct {
    scene: Scene,
    world: World.Raw,

    pub fn intoInternal(self: @This(), gpa: Allocator, io: Io, source_path: []const u8) !Config {
        var rt: Config = .{};
        errdefer rt.deinit(gpa);
        rt.scene = self.scene;
        rt.world = try self.world.intoInternal(gpa, io, source_path);
        return rt;
    }
};

pub fn deinit(self: *Config, gpa: Allocator) void {
    self.world.deinit(gpa);
}

pub fn fromZonFile(gpa: Allocator, io: Io, dir: Io.Dir, path: []const u8) !Config {
    const source = try pre.process(gpa, io, dir, path);
    defer gpa.free(source);

    var diagnostics: std.zon.parse.Diagnostics = .{};
    defer diagnostics.deinit(gpa);

    const parsed = std.zon.parse.fromSliceAlloc(Raw, gpa, source, &diagnostics, .{}) catch |err| {
        var errors = diagnostics.iterateErrors();
        while (errors.next()) |e| {
            const loc = e.getLocation(&diagnostics);
            const msg = e.fmtMessage(&diagnostics);
            std.log.err("in {s}:{d}:{d}: {f}\n", .{ path, loc.line + 1, loc.column + 1, msg });

            var notes = e.iterateNotes(&diagnostics);
            while (notes.next()) |note| {
                const note_loc = note.getLocation(&diagnostics);
                const note_msg = note.fmtMessage(&diagnostics);
                std.log.info("in {s}:{d}:{d}: {f}\n", .{ path, note_loc.line + 1, note_loc.column + 1, note_msg });
            }
        }
        return err;
    };
    return try parsed.intoInternal(gpa, io, path);
}

pub fn render(self: *Config, gpa: Allocator, io: Io, dir: Io.Dir) !void {
    errdefer std.log.err("an error occured while rendering", .{});
    try self.scene.render(gpa, io, dir, &self.world);
}
