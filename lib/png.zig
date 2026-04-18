// TODO: Possibly use pure zig implementation of zlib.

const std = @import("std");
const flate = std.compress.flate;
const Endian = std.builtin.Endian;

/// Writes a true color PNG with 8 as bit depth using the method `render` from a `renderer`.
///
/// The `renderer` should have a method `render(self, x: u32, y: u32) [3]u8`.
/// The `render` function will be used to compute the color of each iterated pixel.
pub fn writeTrueColor8(
    allocator: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    width: u32,
    height: u32,
    renderer: anytype,
) !void {
    var file_writer_buf: [1 << 16]u8 = undefined;
    var file_writer = file.writer(io, &file_writer_buf);
    const file_writer_interface = &file_writer.interface;

    // PNG magic.
    try file_writer_interface.writeAll(&.{ 137, 80, 78, 71, 13, 10, 26, 10 });

    // IHDR chunk.
    var ihdr_data: [13]u8 = undefined;
    var ihdr_data_writer = std.Io.Writer.fixed(&ihdr_data);

    try ihdr_data_writer.writeInt(u32, width, Endian.big);
    try ihdr_data_writer.writeInt(u32, height, Endian.big);
    try ihdr_data_writer.writeInt(u8, 8, Endian.big); // Bit depth.
    try ihdr_data_writer.writeInt(u8, 2, Endian.big); // Color type: True color.
    try ihdr_data_writer.writeInt(u8, 0, Endian.big); // Compression method: default.
    try ihdr_data_writer.writeInt(u8, 0, Endian.big); // Filter method: default.
    try ihdr_data_writer.writeInt(u8, 0, Endian.big); // Interlace Method: none.

    try writeChunk(file_writer_interface, "IHDR".*, &ihdr_data);

    // IDAT chunk.
    var scanline = try std.ArrayList(u8).initCapacity(allocator, width * 3 + 1);
    defer scanline.deinit(allocator);

    const raw_row = try allocator.alloc(u8, width * 3);
    defer allocator.free(raw_row);

    const prev_row = try allocator.alloc(u8, width * 3);
    defer allocator.free(prev_row);
    @memset(prev_row, 0);

    var scanline_candidates: [5][]u8 = undefined;
    inline for (&scanline_candidates) |*c| c.* = try allocator.alloc(u8, width * 3);
    defer inline for (&scanline_candidates) |c| allocator.free(c);

    var compressed: std.Io.Writer.Allocating = try .initCapacity(allocator, height * (width + 1));
    defer compressed.deinit();

    var zlib_buf: [flate.max_window_len]u8 = undefined;
    var zlib = try flate.Compress.init(&compressed.writer, &zlib_buf, .zlib, .best);

    for (0..height) |y| {
        for (0..width) |x| {
            const color: [3]u8 = renderer.render(@intCast(x), @intCast(y));
            raw_row[x * 3 ..][0..3].* = color;
        }

        var best_filter: u8 = 0;
        var best_score: u64 = std.math.maxInt(u64);
        for (0..5) |f| {
            applyFilter(@intCast(f), raw_row, prev_row, scanline_candidates[f]);
            const score = filterScore(scanline_candidates[f]);
            if (score < best_score) {
                best_score = score;
                best_filter = @intCast(f);
            }
        }

        scanline.clearRetainingCapacity();
        scanline.appendAssumeCapacity(best_filter);
        scanline.appendSliceAssumeCapacity(scanline_candidates[best_filter]);

        try zlib.writer.writeAll(scanline.items);

        @memcpy(prev_row, raw_row);
    }

    try zlib.writer.flush();
    try zlib.finish();

    try writeChunk(file_writer_interface, "IDAT".*, compressed.written());
    try writeChunk(file_writer_interface, "IEND".*, &.{});

    try file_writer_interface.flush();
}

fn applyFilter(filter: u8, raw: []const u8, prev: []const u8, out: []u8) void {
    for (raw, 0..) |x, i| {
        const a: u8 = if (i >= 3) raw[i - 3] else 0;
        const b: u8 = prev[i];
        const c: u8 = if (i >= 3) prev[i - 3] else 0;
        out[i] = switch (filter) {
            0 => x,
            1 => x -% a,
            2 => x -% b,
            3 => x -% @as(u8, @intCast((@as(u16, a) + @as(u16, b)) / 2)),
            4 => x -% paethPredictor(a, b, c),
            else => unreachable,
        };
    }
}

fn filterScore(filtered: []const u8) u64 {
    var sum: u64 = 0;
    for (filtered) |b| {
        const s: i8 = @bitCast(b);
        sum += @abs(s);
    }
    return sum;
}

fn paethPredictor(a: u8, b: u8, c: u8) u8 {
    const ai: i16 = a;
    const bi: i16 = b;
    const ci: i16 = c;
    const p = ai + bi - ci;
    const pa = @abs(p - ai);
    const pb = @abs(p - bi);
    const pc = @abs(p - ci);
    if (pa <= pb and pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

fn writeChunk(w: *std.Io.Writer, typ: [4]u8, data: []const u8) !void {
    try w.writeInt(u32, @intCast(data.len), Endian.big);
    try w.writeAll(&typ);
    try w.writeAll(data);
    try w.writeInt(u32, crcChunk(typ, data), Endian.big);
}

fn crcChunk(typ: [4]u8, data: []const u8) u32 {
    var c: u32 = 0xffffffff;
    c = updateCrc(c, &typ);
    c = updateCrc(c, data);
    return c ^ 0xffffffff;
}

const crc_table: [256]u32 = blk: {
    @setEvalBranchQuota(4096);
    var table: [256]u32 = undefined;
    for (&table, 0..) |*c, n| {
        c.* = @intCast(n);
        for (0..8) |_| {
            if (c.* & 1 > 0) {
                c.* = 0xedb88320 ^ (c.* >> 1);
            } else {
                c.* = c.* >> 1;
            }
        }
    }
    break :blk table;
};

fn updateCrc(crc_: u32, buf: []const u8) u32 {
    var c: u32 = crc_;
    for (buf) |n| {
        c = crc_table[(c ^ n) & 0xff] ^ (c >> 8);
    }
    return c;
}

test {
    std.testing.refAllDecls(@This());
}
