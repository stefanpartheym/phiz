const m = @import("m");
const Body = @import("./Body.zig");
const BodyId = @import("./BodyId.zig");

pub const Type = enum {
    dynamic_static,
    dynamic_dynamic,
};

type: Type,
body_a: BodyId,
body_b: BodyId,
mtv: m.Vec2,
normal: m.Vec2,
