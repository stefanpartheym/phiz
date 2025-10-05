const m = @import("m");
const Body = @import("./Body.zig");
const Collision = @import("./Collision.zig");

body_a: *Body,
body_b: *Body,
collision: Collision,
/// Set to true to disable physics resolution for this collision
disable_physics: bool,
