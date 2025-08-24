const std = @import("std");
const rl = @import("raylib");
const phiz = @import("phiz");
const m = phiz.m;

const display_size = m.Vec2_i32.new(800, 600);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.setTargetFPS(60);
    rl.setConfigFlags(.{ .window_highdpi = true });
    rl.initWindow(display_size.x(), display_size.y(), "phiz-example");
    defer rl.closeWindow();

    var state = State.init(allocator);
    defer state.deinit();
    try setup(&state);

    while (state.running) {
        const dt = rl.getFrameTime();
        try input(&state);
        try update(&state, dt);
        render(&state);
    }
}

fn setup(state: *State) !void {
    const display_size_f32 = display_size.cast(f32);
    const collider_size = 20;
    // Add a static ground body.
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(0, display_size_f32.y() - collider_size),
        m.Vec2.new(display_size_f32.x(), collider_size),
    ));
}

fn input(state: *State) !void {
    if (rl.windowShouldClose() or rl.isKeyDown(.q)) {
        state.running = false;
    }

    if (rl.isMouseButtonPressed(.left)) {
        const mouse_pos = rl.getMousePosition();
        _ = try state.world.addBody(phiz.Body.new(
            .dynamic,
            m.Vec2.new(mouse_pos.x, mouse_pos.y),
            m.Vec2.new(25, 25),
        ));
    }
}

fn update(state: *State, dt: f32) !void {
    try state.world.update(dt);
}

fn render(state: *State) void {
    rl.beginDrawing();
    rl.clearBackground(rl.Color.black);
    for (state.world.bodies.items) |body| {
        renderBody(body);
    }
    for (state.world.bodies.items) |body| {
        renderBodyDebug(body);
    }
    renderHud(state);
    rl.endDrawing();
}

fn renderBody(body: phiz.Body) void {
    rl.drawRectangleV(
        rl.Vector2.init(body.position.x(), body.position.y()),
        rl.Vector2.init(body.size.x(), body.size.y()),
        rl.Color.gray,
    );
}

fn renderBodyDebug(body: phiz.Body) void {
    const aabb = body.getAabb();
    const aabb_pos = aabb.min;
    const aabb_size = aabb.getSize();
    rl.drawRectangleLinesEx(
        rl.Rectangle.init(
            aabb_pos.x(),
            aabb_pos.y(),
            aabb_size.x(),
            aabb_size.y(),
        ),
        1,
        rl.Color.red,
    );
    const body_center = body.getCenter();
    const body_velocity = body.getCenter().add(body.velocity.scale(0.1));
    if (body.isDynamic()) {
        rl.drawLineV(
            rl.Vector2.init(body_center.x(), body_center.y()),
            rl.Vector2.init(body_velocity.x(), body_velocity.y()),
            rl.Color.red,
        );
    }
}

fn renderHud(state: *State) void {
    const offset: i32 = 10;
    const font_size: i32 = 20;
    var text_buf: [128]u8 = undefined;
    const bodies_text = std.fmt.bufPrintZ(
        &text_buf,
        "Bodies: {d}",
        .{state.world.bodies.items.len},
    ) catch unreachable;
    rl.drawFPS(offset, offset);
    rl.drawText(
        bodies_text,
        offset,
        font_size + offset * 2,
        font_size,
        rl.Color.ray_white,
    );
}

const State = struct {
    const Self = @This();

    running: bool,
    world: phiz.World,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .running = true,
            .world = phiz.World.init(allocator, null),
        };
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
    }
};
