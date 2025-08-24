const m = @import("m");

const Aabb = @import("./Aabb.zig");

const Self = @This();

pub const BodyType = enum {
    static,
    dynamic,
};

type: BodyType,
position: m.Vec2,
size: m.Vec2,
velocity: m.Vec2,
acceleration: m.Vec2,
mass: f32,
inv_mass: f32,
terminal_velocity: f32,

pub fn new(body_type: BodyType, position: m.Vec2, size: m.Vec2) Self {
    const default_mass = 1;
    const default_terminal_velocity = 1000;
    return Self{
        .type = body_type,
        .position = position,
        .size = size,
        .velocity = m.Vec2.zero(),
        .acceleration = m.Vec2.zero(),
        .mass = switch (body_type) {
            .static => 0,
            .dynamic => default_mass,
        },
        .inv_mass = switch (body_type) {
            .static => 0,
            .dynamic => 1 / default_mass,
        },
        .terminal_velocity = switch (body_type) {
            .static => 0,
            .dynamic => default_terminal_velocity,
        },
    };
}

pub fn isStatic(self: Self) bool {
    return self.type == .static;
}

pub fn isDynamic(self: Self) bool {
    return self.type == .dynamic;
}

pub fn getAabb(self: Self) Aabb {
    return Aabb{
        .min = self.position,
        .max = self.position.add(self.size),
    };
}

pub fn getCenter(self: Self) m.Vec2 {
    return self.position.add(self.size.scale(0.5));
}

pub fn setMass(self: *Self, value: f32) void {
    self.mass = value;
    self.inv_mass = 1 / value;
}

pub fn applyForce(self: *Self, force: m.Vec2) void {
    if (self.isStatic()) return;
    self.acceleration = self.acceleration.add(force.scale(self.inv_mass));
}

pub fn applyImpulse(self: *Self, impulse: m.Vec2) void {
    if (self.isStatic()) return;
    self.velocity = self.velocity.add(impulse.scale(self.inv_mass));
}

/// v += a * dt
pub fn accelerate(self: *Self, dt: f32) void {
    if (self.isStatic()) return;
    self.velocity = self.velocity.add(self.acceleration.scale(dt));

    // Clamp to terminal velocity
    const speed = self.velocity.length();
    if (speed > self.terminal_velocity) {
        self.velocity = self.velocity.norm().scale(self.terminal_velocity);
    }
}

/// x += v * dt
pub fn integrate(self: *Self, dt: f32) void {
    if (self.isStatic()) return;
    self.position = self.position.add(self.velocity.scale(dt));
}
