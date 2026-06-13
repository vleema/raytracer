const std = @import("std");

const raytracer = @import("raytracer.zig");

// TODO: Implement utilities for specifying raytracer options.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena;
    const allocator = arena.allocator();
    const io = init.io;

    const cwd = std.Io.Dir.cwd();
    var rt = raytracer.RT3.fromZonFile(allocator, io, cwd, "scene.zon") catch |err| {
        std.log.err("unable to parse scene description: {any}", .{err});
        std.process.exit(1);
    };
    try rt.render(allocator, io, cwd);
}

test {
    std.testing.refAllDecls(@This());
}
