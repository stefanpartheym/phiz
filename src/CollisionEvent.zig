const m = @import("m");
const Collision = @import("./Collision.zig");

collision: Collision,
/// Set to true to disable physics resolution for this collision
disable_physics: bool,
