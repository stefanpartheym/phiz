const std = @import("std");
const rl = @import("raylib");
const phiz = @import("phiz");
const m = phiz.m;
const common = @import("./common.zig");
const State = common.State;

const DISPLAY_SIZE = m.Vec2_i32.new(800, 600);
const TARGET_FPS = 60;
const PHYSICS_TIMESTEP: f32 = 1.0 / 60.0;
const PHYSICS_SUBSTEPS = 4;
const PLAYER_SPEED_GROUND = 900;
const PLAYER_SPEED_AIR = 150;
const PLAYER_DAMPING_GROUND = 3;
const PLAYER_DAMPING_AIR = 0;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.setTargetFPS(TARGET_FPS);
    rl.setConfigFlags(.{ .window_highdpi = true });
    rl.initWindow(DISPLAY_SIZE.x(), DISPLAY_SIZE.y(), "phiz example: platformer");
    defer rl.closeWindow();

    var state = State.init(allocator, .{});
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
    _ = try state.world.addBody(phiz.Body.new(.dynamic, .{
        .position = m.Vec2.new(display_size_f32.x() - 100, 100),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(50, 50) } },
        .restitution = 0.8,
        .damping = 1.5,
    }));

    // Ground
    _ = try state.world.addBody(phiz.Body.new(.static, .{
        .position = m.Vec2.new(0, display_size_f32.y() - collider_size),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(display_size_f32.x(), collider_size) } },
    }));
    // Left wall
    _ = try state.world.addBody(phiz.Body.new(.static, .{
        .position = m.Vec2.new(0, display_size_f32.y() / 2),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(collider_size, display_size_f32.y() / 2) } },
    }));
    // Right wall
    _ = try state.world.addBody(phiz.Body.new(.static, .{
        .position = m.Vec2.new(display_size_f32.x() - collider_size, display_size_f32.y() / 2),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(collider_size, display_size_f32.y() / 2) } },
    }));

    // Platforms
    const platform_shape = phiz.Body.Shape{ .rectangle = .{ .size = m.Vec2.new(200, collider_size / 2) } };
    _ = try state.world.addBody(phiz.Body.new(.static, .{ .position = m.Vec2.new(450, 450), .shape = platform_shape }));
    _ = try state.world.addBody(phiz.Body.new(.static, .{ .position = m.Vec2.new(50, 300), .shape = platform_shape }));

    // Player
    state.player = try state.world.addBody(phiz.Body.new(.dynamic, .{
        .position = m.Vec2.new(100, 100),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(25, 50) } },
        .restitution = 0.8,
    }));
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

    if (rl.isKeyPressed(.enter)) {
        state.debugger.produceTime(1.0 / 60.0);
    }

    if (rl.isMouseButtonPressed(.left) or rl.isMouseButtonPressed(.right)) {
        const mouse_pos = rl.getMousePosition();
        _ = try state.world.addBody(phiz.Body.new(if (rl.isMouseButtonPressed(.left)) .dynamic else .static, .{
            .position = m.Vec2.new(mouse_pos.x, mouse_pos.y),
            .shape = if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift))
                .{ .circle = .{ .radius = 12.5 } }
            else
                .{ .rectangle = .{ .size = m.Vec2.new(25, 25) } },
            .restitution = if (rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt)) 0.5 else 0,
            .damping = 1.5,
        }));
    }

    //
    // Player input
    //
    // NOTE:
    // Since player movement is applied in the physics update step, we need to
    // make sure, input from a previous frame is carried over to the next frame,
    // until the next physics update runs.
    // This is why, we're not overwriting the input state with empty values,
    // when there was no input in the current frame.
    //

    // Movement
    const movement_input = if (rl.isKeyDown(.h) or rl.isKeyDown(.a) or rl.isKeyDown(.left))
        m.Vec2.left()
    else if (rl.isKeyDown(.l) or rl.isKeyDown(.d) or rl.isKeyDown(.right))
        m.Vec2.right()
    else
        null;

    if (movement_input) |movement| {
        state.input.movement = movement;
    }

    // Jump
    if (rl.isKeyPressed(.space)) {
        state.input.jump = true;
    }
}

fn update(state: *State, dt: f32) !void {
    if (state.physics_enabled) {
        state.accumulator += dt;
        const run_physics = state.accumulator >= PHYSICS_TIMESTEP;
        while (state.accumulator >= PHYSICS_TIMESTEP) {
            state.accumulator -= PHYSICS_TIMESTEP;
            applyPlayerInput(state);
            try state.world.update(PHYSICS_TIMESTEP, PHYSICS_SUBSTEPS);
            updatePlayerDamping(state);
        }

        // Clear input state, if physics ran at least once this frame.
        if (run_physics) {
            state.input.clear();
        }
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

/// Apply forces and implulses to the player body based on input state.
fn applyPlayerInput(state: *State) void {
    const player_body = state.world.getBody(state.player);

    // Handle horizontal movement
    if (state.input.movement.x() != 0) {
        const player_speed: f32 = if (bodyIsGrounded(player_body)) PLAYER_SPEED_GROUND else PLAYER_SPEED_AIR;
        player_body.applyForce(state.input.movement.scale(player_speed));
    } else {
        const deceleration_factor: f32 = if (bodyIsGrounded(player_body)) 10 else 1;
        const deceleration = -player_body.velocity.x() * deceleration_factor;
        player_body.applyForce(m.Vec2.new(deceleration, 0));
    }

    // Handle jump
    if (state.input.jump and bodyIsGrounded(player_body)) {
        player_body.applyImpulse(m.Vec2.new(0, -620));
    }
}

/// Update player damping based on whether the player is on the ground or in the air.
fn updatePlayerDamping(state: *State) void {
    const player_body = state.world.getBody(state.player);
    player_body.damping = if (bodyIsGrounded(player_body))
        PLAYER_DAMPING_GROUND
    else
        PLAYER_DAMPING_AIR;
}

fn bodyIsGrounded(body: *phiz.Body) bool {
    return body.penetration.y() < 0;
}
