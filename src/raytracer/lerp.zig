const std = @import("std");

const Pixel = @import("Pixel.zig");
const Color = @import("Color.zig");

/// Executes a bilinear interpolation of pixels.
pub fn bilerp(
    tl: Pixel,
    tr: Pixel,
    bl: Pixel,
    br: Pixel,
    pos: [2]f32,
) Color {
    const horizontal_factor = factor(@floatFromInt(tl.pos[0]), @floatFromInt(tr.pos[0]), pos[0]);
    const vertical_factor = factor(@floatFromInt(tl.pos[1]), @floatFromInt(bl.pos[1]), pos[1]);
    const top = tl.color.lerp(tr.color, horizontal_factor);
    const bot = bl.color.lerp(br.color, horizontal_factor);
    return top.lerp(bot, vertical_factor);
}

fn factor(x1: f32, x2: f32, x: f32) f32 {
    return std.math.clamp((x - x1) / (x2 - x1), 0, 1);
}
