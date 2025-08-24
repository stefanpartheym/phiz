const std = @import("std");
const m = @import("m");

pub fn add(a: m.Vec2, b: m.Vec2) m.Vec2 {
    return a.add(b);
}

test "basic add functionality" {
    try std.testing.expect(add(m.Vec2.new(1, 2), m.Vec2.new(3, 4)).eql(m.Vec2.new(4, 6)));
}
