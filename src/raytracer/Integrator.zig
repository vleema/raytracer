const xml = @import("xml");

pub const Integrator = union(enum) {
    flat,

    pub fn fromXml(elem: *const xml.Element) !@This() {
        if (elem.queryAttribute("type", "flat")) |_| {
            return .flat;
        }
        return error.InvalidIntegratorType;
    }
};
