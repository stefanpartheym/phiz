const CollisionEvent = @import("./CollisionEvent.zig");
const World = @import("./World.zig");

/// Callback function type for collision events.
pub const CollisionCallback = *const fn (world: *World, event: *CollisionEvent) void;

const Self = @This();

pub const init: Self = .{ .on_contact = null };

on_contact: ?CollisionCallback,
