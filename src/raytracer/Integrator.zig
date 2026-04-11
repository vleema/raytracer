const std = @import("std");
const xml = @import("xml");

const log = std.log.scoped(.integrator);

pub const Integrator = union(enum) {
    flat,

    pub fn fromXml(elem: *const xml.Element) !@This() {
        const typ = elem.queryAttribute("type", null) orelse
            return error.ExpectedIntegratorType;

        if (std.mem.eql(u8, typ, "flat")) {
            return .flat;
        }
        log.err("expected one of ['flat'], found {s}", .{typ});
        return error.InvalidIntegratorType;
    }
};
