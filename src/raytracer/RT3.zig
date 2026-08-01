const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const pre = @import("pre");

const Scene = @import("Scene.zig");
const World = @import("World.zig");

const RT3 = @This();

scene: Scene = .{},
world: World = .{},

pub const Raw = struct {
    scene: Scene,
    world: World.Raw,

    pub fn intoInternal(self: @This(), gpa: Allocator, io: Io, source_path: []const u8) !RT3 {
        var rt: RT3 = .{};
        errdefer rt.deinit(gpa);
        rt.scene = self.scene;
        rt.world = try self.world.intoInternal(gpa, io, source_path);
        return rt;
    }
};

pub fn deinit(self: *RT3, gpa: Allocator) void {
    self.world.deinit(gpa);
}

pub fn fromZonFile(gpa: Allocator, io: Io, dir: Io.Dir, path: []const u8) !RT3 {
    const source = try pre.process(gpa, io, dir, path);
    defer gpa.free(source);

    var diag: std.zon.parse.Diagnostics = .{};
    defer diag.deinit(gpa);

    const parsed = std.zon.parse.fromSliceAlloc(Raw, gpa, source, &diag, .{}) catch |err| {
        var errors = diag.iterateErrors();
        while (errors.next()) |e| {
            const loc = e.getLocation(&diag);
            const msg = e.fmtMessage(&diag);
            std.log.err("in {s}:{d}:{d}: {f}\n", .{ path, loc.line + 1, loc.column + 1, msg });

            var notes = e.iterateNotes(&diag);
            while (notes.next()) |note| {
                const note_loc = note.getLocation(&diag);
                const note_msg = note.fmtMessage(&diag);
                std.log.info("in {s}:{d}:{d}: {f}\n", .{ path, note_loc.line + 1, note_loc.column + 1, note_msg });
            }
        }
        return err;
    };
    return try parsed.intoInternal(gpa, io, path);
}

pub fn render(self: *RT3, gpa: Allocator, io: Io, dir: Io.Dir) !void {
    errdefer std.log.err("an error occured while rendering", .{});
    try self.scene.render(gpa, io, dir, &self.world);
}
