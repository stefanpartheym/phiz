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
const DIAGONAL_FACTOR: f32 = 1.0 / @sqrt(@as(f32, 2));
const PLAYER_SPEED = 1000;
const PLAYER_DAMPING = 5;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.setTargetFPS(TARGET_FPS);
    rl.setConfigFlags(.{ .window_highdpi = true });
    rl.initWindow(DISPLAY_SIZE.x(), DISPLAY_SIZE.y(), "phiz example: top-down");
    defer rl.closeWindow();

    var state = State.init(allocator, .{ .physics_config = .{ .gravity = m.Vec2.zero() } });
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
    const display_size_f32: m.Vec2 = DISPLAY_SIZE.cast(f32);
    const collider_size = 20;
    // Top
    _ = try state.world.addBody(phiz.Body.new(.static, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(display_size_f32.x(), collider_size) } },
    }));
    // Bottom
    _ = try state.world.addBody(phiz.Body.new(.static, .{
        .position = m.Vec2.new(0, display_size_f32.y() - collider_size),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(display_size_f32.x(), collider_size) } },
    }));
    // Left
    _ = try state.world.addBody(phiz.Body.new(.static, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(collider_size, display_size_f32.y()) } },
    }));
    // Right
    _ = try state.world.addBody(phiz.Body.new(.static, .{
        .position = m.Vec2.new(display_size_f32.x() - collider_size, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(collider_size, display_size_f32.y()) } },
    }));

    // Add pillars.
    const display_half_size = display_size_f32.scale(0.5);
    const pillar_size = 50;
    const pillar_half_size = pillar_size / 2;
    const pillar_offset = 50;
    const pillar_top_left = m.Vec2.new(display_half_size.x() - pillar_offset - pillar_half_size, display_half_size.y() - pillar_offset - pillar_half_size);
    const pillar_top_right = m.Vec2.new(display_half_size.x() + pillar_offset - pillar_half_size, display_half_size.y() - pillar_offset - pillar_half_size);
    const pillar_bottom_left = m.Vec2.new(display_half_size.x() - pillar_offset - pillar_half_size, display_half_size.y() + pillar_offset - pillar_half_size);
    const pillar_bottom_right = m.Vec2.new(display_half_size.x() + pillar_offset - pillar_half_size, display_half_size.y() + pillar_offset - pillar_half_size);
    const pillar_shape = phiz.Body.Shape{ .rectangle = .{ .size = m.Vec2.new(pillar_size, pillar_size) } };

    _ = try state.world.addBody(phiz.Body.new(.static, .{ .position = pillar_top_left, .shape = pillar_shape }));
    _ = try state.world.addBody(phiz.Body.new(.static, .{ .position = pillar_top_right, .shape = pillar_shape }));
    _ = try state.world.addBody(phiz.Body.new(.static, .{ .position = pillar_bottom_left, .shape = pillar_shape }));
    _ = try state.world.addBody(phiz.Body.new(.static, .{ .position = pillar_bottom_right, .shape = pillar_shape }));

    // Add player.
    state.player = try state.world.addBody(phiz.Body.new(.dynamic, .{
        .position = display_half_size,
        .shape = .{ .circle = .{ .radius = 25 } },
        .restitution = 0.8,
    }));
    const player_body = state.world.getBody(state.player);
    player_body.damping = PLAYER_DAMPING;
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

    if (rl.isKeyPressed(.enter)) {
        state.debugger.produceTime(1.0 / 60.0);
    }

    //
    // Player input
    //

    // Horizontal movement
    var direction_h = m.Vec2.zero();

    // Left
    if (rl.isKeyDown(.h) or rl.isKeyDown(.a) or rl.isKeyDown(.left)) {
        direction_h = m.Vec2.left();
    }
    // Right
    else if (rl.isKeyDown(.l) or rl.isKeyDown(.d) or rl.isKeyDown(.right)) {
        direction_h = m.Vec2.right();
    }

    // Vertical movement
    var direction_v = m.Vec2.zero();

    // Up
    if (rl.isKeyDown(.k) or rl.isKeyDown(.w) or rl.isKeyDown(.up)) {
        direction_v = m.Vec2.up().negate();
    }
    // Down
    else if (rl.isKeyDown(.j) or rl.isKeyDown(.s) or rl.isKeyDown(.down)) {
        direction_v = m.Vec2.down().negate();
    }

    const direction = direction_h.add(direction_v);

    if (!direction.eql(m.Vec2.zero())) {
        state.input.movement = direction;
    }
}

fn update(state: *State, dt: f32) !void {
    if (state.physics_enabled) {
        state.accumulator += dt;
        const run_physics = state.accumulator >= PHYSICS_TIMESTEP;
        const player_body = state.world.getBody(state.player);
        while (state.accumulator >= PHYSICS_TIMESTEP) {
            state.accumulator -= PHYSICS_TIMESTEP;
            {
                const movement = state.input.movement;
                const is_diagonal_movement = movement.x() != 0 and movement.y() != 0;
                // In case of diagonal movement, speed must be modulated by the
                // diagonal factor to avoid diagonal movement being faster.
                const scaled_speed = PLAYER_SPEED * if (is_diagonal_movement) DIAGONAL_FACTOR else 1;
                // Apply forces to the player body.
                player_body.applyForce(state.input.movement.scale(scaled_speed));
            }
            // Update physics.
            try state.world.update(PHYSICS_TIMESTEP, PHYSICS_SUBSTEPS);
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
