const std = @import("std");

const Token = union(enum) {
    illegal,
    tag_start,
    tag_end,
    eq,
    end_tag_start,
    self_close,
    slash,
    literal: []const u8,
    identifier: []const u8,

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        try writer.print("{s}", .{@typeName(@This())});
        switch (self) {
            .illegal => try writer.print("{{ .illegal }}", .{}),
            .tag_start => try writer.print("{{ .tag_start }}", .{}),
            .tag_end => try writer.print("{{ .tag_end }}", .{}),
            .eq => try writer.print("{{ .eq }}", .{}),
            .end_tag_start => try writer.print("{{ .end_tag_start }}", .{}),
            .self_close => try writer.print("{{ .self_close }}", .{}),
            .slash => try writer.print("{{ .slash }}", .{}),
            .literal => |lit| try writer.print("{{ .literal = \"{s}\" }}", .{lit}),
            .identifier => |id| try writer.print("{{ .identifier = \"{s}\" }}", .{id}),
        }
    }
};

