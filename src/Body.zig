const m = @import("m");
const Aabb = @import("./Aabb.zig");

pub const BodyType = enum {
    static,
    dynamic,
};

pub const Config = struct {
    position: m.Vec2,
    size: m.Vec2,
    mass: f32 = 1,
    damping: f32 = 0,
    restitution: f32 = 0,
};

const Self = @This();

type: BodyType,
position: m.Vec2,
size: m.Vec2,
velocity: m.Vec2,
acceleration: m.Vec2,
damping: f32,
mass: f32,
inv_mass: f32,
/// Coefficient of restitution:
/// - 0 = fully inelastic (stop)
/// - 1 = fully elastic (bounce)
restitution: f32,
/// Contains the deepest penetration caused by collisions on each axis.
penetration: m.Vec2,

pub fn new(body_type: BodyType, config: Config) Self {
    return Self{
        .type = body_type,
        .position = config.position,
        .size = config.size,
        .velocity = m.Vec2.zero(),
        .acceleration = m.Vec2.zero(),
        .damping = config.damping,
        .mass = switch (body_type) {
            .static => 0,
            .dynamic => config.mass,
        },
        .inv_mass = switch (body_type) {
            .static => 0,
            .dynamic => 1 / config.mass,
        },
        .restitution = config.restitution,
        .penetration = m.Vec2.zero(),
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
}

pub fn applyDamping(self: *Self, dt: f32) void {
    if (self.isStatic()) return;
    if (self.damping != 0) {
        self.velocity = self.velocity.scale(@exp(-self.damping * dt));
    }
}

/// x += v * dt
pub fn integrate(self: *Self, dt: f32) void {
    if (self.isStatic()) return;
    self.position = self.position.add(self.velocity.scale(dt));
}

/// Accumulate the deepest penetration caused by collisions on each axis.
pub fn accumulatePenetration(self: *Self, value: m.Vec2) void {
    if (@abs(value.x()) > @abs(self.penetration.x())) self.penetration.xMut().* = value.x();
    if (@abs(value.y()) > @abs(self.penetration.y())) self.penetration.yMut().* = value.y();
}
