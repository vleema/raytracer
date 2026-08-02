const std = @import("std");

pub const Config = @import("Config.zig");

test {
    std.testing.refAllDecls(@This());
}
