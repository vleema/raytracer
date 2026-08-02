const std = @import("std");

const rt = @import("raytracer");

// TODO: Implement utilities for specifying raytracer options, i.e.
// - Number of threads on the cpu.
// - If it will use the gpu.
// TODO: Add a progress bar.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena;
    const allocator = arena.allocator();
    const io = init.io;

    const cwd = std.Io.Dir.cwd();
    const scene_file = if (init.minimal.args.vector.len > 1)
        std.mem.span(init.minimal.args.vector[1])
    else
        "scene.zon";

    var config = rt.Config.fromZonFile(allocator, io, cwd, scene_file) catch
        std.process.fatal("error parsing config file: '{s}'", .{scene_file});

    try config.render(allocator, io, cwd);
}
