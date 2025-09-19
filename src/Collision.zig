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
normal: m.Vec2, // TODO: Currently, not in use.

pub fn determineType(body_a: *const Body, body_b: *const Body) Type {
    if (body_a.isStatic() or body_b.isStatic()) {
        return .dynamic_static;
    } else {
        return .dynamic_dynamic;
    }
}
