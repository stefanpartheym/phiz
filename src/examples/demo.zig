//! Basic demo with multiple dynamic bodies crashing into static circle colliders.
//! This mainly provides a reliable scenario for performance testing with tracy.

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.setTargetFPS(TARGET_FPS);
    rl.setConfigFlags(.{ .window_highdpi = true });
    rl.initWindow(DISPLAY_SIZE.x(), DISPLAY_SIZE.y(), "phiz example: demo");
    defer rl.closeWindow();

    var state = State.init(allocator, .{
        .debugger_config = .{
            .physics_timeout = 10,
            .frame_stepping_enabled = true,
        },
        .physics_config = .{ .spatial_grid_cell_size = 40 },
    });
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
    const display_size: m.Vec2 = DISPLAY_SIZE.cast(f32);
    const collider_size = 20;
    const collider_left = 250;
    const collider_right = 550;
    const circle_shape = phiz.Body.Shape{ .circle = .{ .radius = 40 } };
    const wall_shape = phiz.Body.Shape{ .rectangle = .{ .size = m.Vec2.new(collider_size, display_size.y()) } };
    const dynamic_shape_rect = phiz.Body.Shape{ .rectangle = .{ .size = m.Vec2.new(collider_size, collider_size) } };
    const dynamic_shape_circ = phiz.Body.Shape{ .circle = .{ .radius = collider_size / 2 } };

    _ = try state.world.addBody(phiz.Body.new(
        .static,
        .{
            .position = m.Vec2.new(0, display_size.y() - collider_size),
            .shape = .{ .rectangle = .{ .size = m.Vec2.new(display_size.x(), collider_size) } },
        },
    ));
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        .{
            .position = m.Vec2.new(0, 0),
            .shape = wall_shape,
        },
    ));
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        .{
            .position = m.Vec2.new(display_size.x() - collider_size, 0),
            .shape = wall_shape,
        },
    ));

    _ = try state.world.addBody(phiz.Body.new(.static, .{ .position = m.Vec2.new(collider_left, 300), .shape = circle_shape }));
    _ = try state.world.addBody(phiz.Body.new(.static, .{ .position = m.Vec2.new(collider_right, 300), .shape = circle_shape }));

    try spawnDynamicBodies(state, 25, dynamic_shape_rect, m.Vec2.new(collider_left, 0));
    try spawnDynamicBodies(state, 25, dynamic_shape_circ, m.Vec2.new(collider_left, -1000));
    try spawnDynamicBodies(state, 25, dynamic_shape_rect, m.Vec2.new(collider_right, 0));
    try spawnDynamicBodies(state, 25, dynamic_shape_circ, m.Vec2.new(collider_right, -1000));
}

fn spawnDynamicBodies(state: *State, count: usize, shape: phiz.Body.Shape, offset: m.Vec2) !void {
    const size = switch (shape) {
        .circle => |circ| circ.radius / 2,
        .rectangle => |rect| rect.size.x(),
    };
    const shape_offset = if (shape == .rectangle) size / 2 else 0;
    for (0..count) |i| {
        const i_f32: f32 = @floatFromInt(i);
        const sign: f32 = if (i % 2 == 0) -1 else 1;
        _ = try state.world.addBody(phiz.Body.new(.dynamic, .{
            .position = m.Vec2.new(offset.x() - shape_offset + sign * size, offset.y() - i_f32 * size * 2),
            .shape = shape,
            .restitution = 0.8,
            .damping = 0.5,
        }));
    }
}

fn reset(state: *State) !void {
    state.debugger.physics_time = 0;
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
}

fn update(state: *State, dt: f32) !void {
    if (state.physics_enabled and !state.debugger.isPhysicsTimeout()) {
        state.accumulator += dt;
        while (state.accumulator >= PHYSICS_TIMESTEP) {
            state.debugger.physics_time += PHYSICS_TIMESTEP;
            state.accumulator -= PHYSICS_TIMESTEP;
            try state.world.update(PHYSICS_TIMESTEP, PHYSICS_SUBSTEPS);
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

fn bodyIsGrounded(body: *phiz.Body) bool {
    return body.penetration.y() < 0;
}
