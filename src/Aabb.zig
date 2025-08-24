//! Axis-aligned bounding box.

const m = @import("m");

const Self = @This();

min: m.Vec2,
max: m.Vec2,

pub fn new(min: m.Vec2, max: m.Vec2) Self {
    // Make sure the AABB is valid.
    const delta = max.sub(min);
    std.debug.assert(delta.x() >= 0 and delta.y() >= 0);

    return Self{ .min = min, .max = max };
}

/// Checks if this `Aabb` intersects with another `Aabb`.
/// Useful for broadphase collision detection.
pub fn intersects(self: Self, other: Self) bool {
    return self.min.x() < other.max.x() and
        self.max.x() > other.min.x() and
        self.min.y() < other.max.y() and
        self.max.y() > other.min.y();
}

pub fn eql(self: Self, other: Self) bool {
    return self.min.eql(other.min) and self.max.eql(other.max);
}

pub fn getSize(self: Self) m.Vec2 {
    return self.max.sub(self.min);
}

pub fn getHalfSize(self: Self) m.Vec2 {
    return self.getSize().scale(0.5);
}

pub fn getCenter(self: Self) m.Vec2 {
    return self.min.add(self.getHalfSize());
}

//
// Tests
//

const std = @import("std");
const Aabb = Self;

test "new: Should create a valid AABB" {
    const min = m.Vec2.new(0, 0);
    const max = m.Vec2.new(2, 2);
    const aabb = Aabb.new(min, max);
    try std.testing.expect(aabb.min.eql(min));
    try std.testing.expect(aabb.max.eql(max));
}

test "intersects: Should return true for overlapping AABBs" {
    const a = Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const b = Aabb.new(m.Vec2.new(1, 1), m.Vec2.new(3, 3));
    try std.testing.expect(a.intersects(b));
}

test "intersects: Should return true for overlapping AABBs (in negative space)" {
    const a = Aabb.new(m.Vec2.new(-2, -2), m.Vec2.new(0, 0));
    const b = Aabb.new(m.Vec2.new(-3, -3), m.Vec2.new(-1, -1));
    try std.testing.expect(a.intersects(b));
}

test "intersects: Should return true for AABBs just overlapping by epsilon" {
    // Epsilon (2^-23):
    // For f32 it's roughly: 0.00000011920929
    const epsilon = std.math.floatEps(f32);
    const a = Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(1, 1));
    // B's top-left corner is roughly at: (0.9999999, 0.9999999)
    const b = Aabb.new(m.Vec2.new(1 - epsilon, 1 - epsilon), m.Vec2.new(2, 2));
    try std.testing.expect(a.intersects(b));
}

test "intersects: Should return false for AABBs overlapping only on X axis" {
    const a = Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const b = Aabb.new(m.Vec2.new(1.9, 2), m.Vec2.new(3, 3));
    try std.testing.expect(!a.intersects(b));
}

test "intersects: Should return false for AABBs overlapping only on Y axis" {
    const a = Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const b = Aabb.new(m.Vec2.new(2, 1.9), m.Vec2.new(3, 3));
    try std.testing.expect(!a.intersects(b));
}

test "intersects: Should return false for AABBs not overlapping" {
    const a = Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const b = Aabb.new(m.Vec2.new(2, 2), m.Vec2.new(3, 3));
    try std.testing.expect(!a.intersects(b));
}
