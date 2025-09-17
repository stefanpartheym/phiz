const std = @import("std");
const rl = @import("raylib");
const phiz = @import("phiz");
const m = phiz.m;
const common = @import("./common.zig");
const State = common.State;

const DISPLAY_SIZE = m.Vec2_i32.new(800, 600);
const PLAYER_SPEED_GROUND = 900;
const PLAYER_SPEED_AIR = 300;
const PLAYER_DAMPING_GROUND = 3.5;
const PLAYER_DAMPING_AIR = 0.5;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.setTargetFPS(60);
    rl.setConfigFlags(.{ .window_highdpi = true });
    rl.initWindow(DISPLAY_SIZE.x(), DISPLAY_SIZE.y(), "phiz example: platformer");
    defer rl.closeWindow();

    var state = State.init(allocator);
    defer state.deinit();
    try setup(&state);

    while (state.running) {
        const dt = if (state.debugger.frame_stepping_enabled)
            state.debugger.consumeTime()
        else
            rl.getFrameTime();
        try input(&state);
        try update(&state, dt);
        render(&state);
    }
}

fn setup(state: *State) !void {
    const display_size_f32 = DISPLAY_SIZE.cast(f32);
    const collider_size = 20;
    // Moving body
    _ = try state.world.addBody(phiz.Body.new(
        .dynamic,
        m.Vec2.new(display_size_f32.x() - 100, 100),
        m.Vec2.new(50, 50),
    ));

    // Ground
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(0, display_size_f32.y() - collider_size),
        m.Vec2.new(display_size_f32.x(), collider_size),
    ));
    // Left wall
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(0, display_size_f32.y() / 2),
        m.Vec2.new(collider_size, display_size_f32.y() / 2),
    ));
    // Right wall
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(display_size_f32.x() - collider_size, display_size_f32.y() / 2),
        m.Vec2.new(collider_size, display_size_f32.y() / 2),
    ));

    // Low platform
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(450, 450),
        m.Vec2.new(200, collider_size / 2),
    ));
    // High platform
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(50, 300),
        m.Vec2.new(200, collider_size / 2),
    ));

    // Player
    state.player = try state.world.addBody(phiz.Body.new(
        .dynamic,
        m.Vec2.new(100, 100),
        m.Vec2.new(25, 50),
    ));
}

fn reset(state: *State) !void {
    state.world.bodies.clearRetainingCapacity();
    try setup(state);
}

fn input(state: *State) !void {
    if (rl.windowShouldClose() or rl.isKeyDown(.q)) {
        state.running = false;
    }

    if (rl.isKeyPressed(.r)) {
        try reset(state);
    }

    if (rl.isKeyPressed(.p)) {
        state.physics_enabled = !state.physics_enabled;
    }

    if (rl.isKeyPressed(.f1)) {
        state.debugger.frame_stepping_enabled = !state.debugger.frame_stepping_enabled;
    }

    if (rl.isMouseButtonPressed(.left)) {
        const mouse_pos = rl.getMousePosition();
        _ = try state.world.addBody(phiz.Body.new(
            .dynamic,
            m.Vec2.new(mouse_pos.x, mouse_pos.y),
            m.Vec2.new(25, 25),
        ));
    }

    if (rl.isKeyPressed(.enter)) {
        state.debugger.produceTime(1.0 / 60.0);
    }

    // Player movement
    const movement = if (rl.isKeyDown(.h) or rl.isKeyDown(.left))
        m.Vec2.left()
    else if (rl.isKeyDown(.j) or rl.isKeyDown(.down))
        m.Vec2.down().negate()
    else if (rl.isKeyDown(.k) or rl.isKeyDown(.up))
        m.Vec2.up().negate()
    else if (rl.isKeyDown(.l) or rl.isKeyDown(.right))
        m.Vec2.right()
    else
        m.Vec2.zero();

    const player = state.world.getBody(state.player);
    const speed: f32 = if (bodyIsGrounded(player)) PLAYER_SPEED_GROUND else PLAYER_SPEED_AIR;
    player.applyForce(movement.scale(speed));

    // Jump
    if (bodyIsGrounded(player) and rl.isKeyPressed(.space)) {
        player.applyImpulse(m.Vec2.new(0, -700));
    }
}

fn update(state: *State, dt: f32) !void {
    if (state.physics_enabled) {
        const moving_body = state.world.getBody(phiz.BodyId.new(0));
        moving_body.applyForce(m.Vec2.new(-100, 0));
        const player_body = state.world.getBody(state.player);
        if (player_body.penetration.y() < 0) {
            player_body.damping = PLAYER_DAMPING_GROUND;
        } else {
            player_body.damping = PLAYER_DAMPING_AIR;
        }
        try state.world.update(dt);
    }
}

fn render(state: *State) void {
    rl.beginDrawing();
    rl.clearBackground(rl.Color.black);
    for (state.world.bodies.items) |body| {
        common.renderBody(body);
    }
    for (state.world.bodies.items, 0..) |body, index| {
        common.renderBodyDebug(body, index);
    }
    common.renderHud(state);
    rl.endDrawing();
}

fn bodyIsGrounded(body: *phiz.Body) bool {
    return body.penetration.y() < 0;
}
