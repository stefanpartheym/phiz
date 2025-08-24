const std = @import("std");
const m = @import("m");
const Body = @import("./Body.zig");

const Self = @This();

/// Default gravity is more or less earth's gravity:
///   g = 9.81 m/s²
/// Multiplying by 100 to get make it feel realistic.
pub const DEFAULT_GRAVITY = m.Vec2.new(0, 9.81 * 100);

pub const BodyId = struct {
    index: usize,
    pub fn new(index: usize) @This() {
        return @This(){ .index = index };
    }
};

allocator: std.mem.Allocator,
gravity: m.Vec2,
sub_steps: usize,
bodies: std.ArrayList(Body),

pub fn init(allocator: std.mem.Allocator, gravity: ?m.Vec2) Self {
    return Self{
        .allocator = allocator,
        .gravity = gravity orelse DEFAULT_GRAVITY,
        .sub_steps = 3,
        .bodies = std.ArrayList(Body){},
    };
}

pub fn deinit(self: *Self) void {
    self.bodies.deinit(self.allocator);
}

pub fn update(self: *Self, dt: f32) !void {
    // Apply forces.
    for (self.bodies.items) |*body| {
        body.applyForce(self.gravity.scale(body.mass));
        body.accelerate(dt);
    }

    // Integrate all bodies.
    for (self.bodies.items) |*body| {
        body.integrate(dt);
    }

    // Reset accelerations.
    for (self.bodies.items) |*body| {
        body.acceleration = m.Vec2.zero();
    }
}

pub fn addBody(self: *Self, body: Body) !BodyId {
    try self.bodies.append(self.allocator, body);
    return BodyId.new(self.bodies.items.len - 1);
}

pub fn getBody(self: *const Self, handle: BodyId) *Body {
    return &self.bodies.items[handle.index];
}
