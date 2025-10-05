//! Collision filter struct to determine what bodies can collide.

const Self = @This();

/// Default collision filter: Collide with everything.
pub const init: Self = .{
    .layer = 0x0001,
    .mask = 0xFFFF,
    .group_index = 0,
};

/// What layer this body belongs to (single bit)
layer: u16,
/// What layers this body can collide with (bitmask)
mask: u16,
/// Group index for fine-grained control:
/// - Positive: bodies in same group always collide
/// - Negative: bodies in same group never collide
/// - Zero: use layer/mask filtering
group_index: i16 = 0,

/// Check if two filters can collide.
pub fn canCollide(filter_a: Self, filter_b: Self) bool {
    // Group filtering takes precedence
    if (filter_a.group_index != 0 and filter_a.group_index == filter_b.group_index) {
        return filter_a.group_index > 0;
    }
    // Layer/mask filtering
    return (filter_a.mask & filter_b.layer) != 0 and
        (filter_b.mask & filter_a.layer) != 0;
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const std = @import("std");
const CollisionFilter = Self;

test "CollisionFilter.canCollide: Default filters should collide" {
    const filter_a = CollisionFilter.init;
    const filter_b = CollisionFilter.init;
    try std.testing.expect(CollisionFilter.canCollide(filter_a, filter_b));
}

test "CollisionFilter.canCollide: Different layers with matching masks should collide" {
    const filter_a = CollisionFilter{ .layer = 0x0001, .mask = 0x0002, .group_index = 0 };
    const filter_b = CollisionFilter{ .layer = 0x0002, .mask = 0x0001, .group_index = 0 };
    try std.testing.expect(CollisionFilter.canCollide(filter_a, filter_b));
}

test "CollisionFilter.canCollide: Non-matching masks should not collide" {
    const filter_a = CollisionFilter{ .layer = 0x0001, .mask = 0x0002, .group_index = 0 };
    const filter_b = CollisionFilter{ .layer = 0x0004, .mask = 0x0008, .group_index = 0 };
    try std.testing.expect(!CollisionFilter.canCollide(filter_a, filter_b));
}

test "CollisionFilter.canCollide: One-way mask blocking should prevent collision" {
    // filter_a: Can't collide with anything
    const filter_a = CollisionFilter{ .layer = 0x0001, .mask = 0x0000, .group_index = 0 };
    // filter_b: Can collide with everything
    const filter_b = CollisionFilter{ .layer = 0x0002, .mask = 0xFFFF, .group_index = 0 };
    try std.testing.expect(!CollisionFilter.canCollide(filter_a, filter_b));
}

test "CollisionFilter.canCollide: Positive group index should always collide" {
    const filter_a = CollisionFilter{ .layer = 0x0001, .mask = 0x0000, .group_index = 5 };
    const filter_b = CollisionFilter{ .layer = 0x0002, .mask = 0x0000, .group_index = 5 };
    try std.testing.expect(CollisionFilter.canCollide(filter_a, filter_b));
}

test "CollisionFilter.canCollide: Negative group index should never collide" {
    const filter_a = CollisionFilter{ .layer = 0x0001, .mask = 0xFFFF, .group_index = -3 };
    const filter_b = CollisionFilter{ .layer = 0x0001, .mask = 0xFFFF, .group_index = -3 };
    try std.testing.expect(!CollisionFilter.canCollide(filter_a, filter_b));
}

test "CollisionFilter.canCollide: Different group indices should use layer/mask filtering" {
    const filter_a = CollisionFilter{ .layer = 0x0001, .mask = 0x0002, .group_index = 1 };
    const filter_b = CollisionFilter{ .layer = 0x0002, .mask = 0x0001, .group_index = 2 };
    try std.testing.expect(CollisionFilter.canCollide(filter_a, filter_b));
}

test "CollisionFilter.canCollide: Zero group index should use layer/mask filtering" {
    const filter_a = CollisionFilter{ .layer = 0x0001, .mask = 0x0002, .group_index = 0 };
    const filter_b = CollisionFilter{ .layer = 0x0002, .mask = 0x0001, .group_index = 0 };
    try std.testing.expect(CollisionFilter.canCollide(filter_a, filter_b));
}

test "CollisionFilter.canCollide: Multiple layer bits should work correctly" {
    // filter_a: layers 1+2, mask 3+4
    const filter_a = CollisionFilter{ .layer = 0x0003, .mask = 0x000C, .group_index = 0 };
    // filter_b: layer 3, mask 2
    const filter_b = CollisionFilter{ .layer = 0x0004, .mask = 0x0002, .group_index = 0 };
    try std.testing.expect(CollisionFilter.canCollide(filter_a, filter_b));
}
