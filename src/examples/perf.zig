//! Headless performance harness for the phiz physics engine.
//!
//! This runs the exact same scenario as `demo.zig` but WITHOUT raylib/rendering,
//! for a fixed number of physics steps. That makes it deterministic and
//! repeatable, so it is suitable for A/B profiling (e.g. when upgrding to a new
//! Zig version).
//!
//! Run:
//!   zig build run-perf                         # Debug
//!   zig build run-perf -Doptimize=ReleaseFast  # representative of shipped perf
//!   zig build run-perf -Doptimize=ReleaseFast -Dtracy_enable=true  # profile
//!
//! It prints per-step statistics (min / median / p95 / p99 / max), which are
//! far more stable than a single live-capture average. Tweak `STEPS` and
//! `BODIES_PER_GROUP` below to change the workload.

const std = @import("std");
const phiz = @import("phiz");
const tracy = @import("tracy");
const m = phiz.m;

const World = phiz.World(void);
const Body = World.Body;

const PHYSICS_TIMESTEP: f32 = 1.0 / 60.0;
const PHYSICS_SUBSTEPS: usize = 4;

/// Number of physics steps to simulate. Fixed for determinism.
const STEPS: usize = 600;
/// Dynamic bodies per spawn group (4 groups).
const BODIES_PER_GROUP: usize = 120;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var world = World.init(allocator, .{ .spatial_grid_cell_size = 40 });
    defer world.deinit();
    try setup(&world);

    // Collect per-step timings so we can report medians/percentiles instead of
    // a noisy single mean.
    const timings = try allocator.alloc(u64, STEPS);
    defer allocator.free(timings);

    const start = std.time.nanoTimestamp();
    for (0..STEPS) |i| {
        const step_start = std.time.nanoTimestamp();
        try world.update(PHYSICS_TIMESTEP, PHYSICS_SUBSTEPS);
        const step_end = std.time.nanoTimestamp();
        timings[i] = @intCast(step_end - step_start);
        tracy.FrameMark();
    }
    const total: u64 = @intCast(std.time.nanoTimestamp() - start);

    report(world.bodies.items.len, total, timings);
}

fn setup(world: *World) !void {
    const width: f32 = 800;
    const height: f32 = 600;
    const collider_size: f32 = 20;
    const collider_left: f32 = 250;
    const collider_right: f32 = 550;

    const circle_shape: Body.Shape = .{ .circle = .{ .radius = 40 } };
    const wall_shape: Body.Shape = .{ .rectangle = .{ .half_size = m.Vec2.new(collider_size / 2, height / 2) } };
    const dynamic_shape_rect: Body.Shape = .{ .rectangle = .{ .half_size = m.Vec2.new(collider_size / 2, collider_size / 2) } };
    const dynamic_shape_circ: Body.Shape = .{ .circle = .{ .radius = collider_size / 2 } };

    // Floor.
    _ = try world.createBody(Body.new(.static, .{
        .position = m.Vec2.new(width / 2, height - collider_size / 2),
        .shape = .{ .rectangle = .{ .half_size = m.Vec2.new(width / 2, collider_size / 2) } },
    }));
    // Left / right walls.
    _ = try world.createBody(Body.new(.static, .{ .position = m.Vec2.new(collider_size / 2, height / 2), .shape = wall_shape }));
    _ = try world.createBody(Body.new(.static, .{ .position = m.Vec2.new(width - collider_size / 2, height / 2), .shape = wall_shape }));
    // Static obstacle circles.
    _ = try world.createBody(Body.new(.static, .{ .position = m.Vec2.new(collider_left, 300), .shape = circle_shape }));
    _ = try world.createBody(Body.new(.static, .{ .position = m.Vec2.new(collider_right, 300), .shape = circle_shape }));

    // 4 groups of falling dynamic bodies.
    try spawnDynamicBodies(world, BODIES_PER_GROUP, dynamic_shape_rect, m.Vec2.new(collider_left, 0));
    try spawnDynamicBodies(world, BODIES_PER_GROUP, dynamic_shape_circ, m.Vec2.new(collider_left, -2000));
    try spawnDynamicBodies(world, BODIES_PER_GROUP, dynamic_shape_rect, m.Vec2.new(collider_right, 0));
    try spawnDynamicBodies(world, BODIES_PER_GROUP, dynamic_shape_circ, m.Vec2.new(collider_right, -2000));
}

fn spawnDynamicBodies(world: *World, count: usize, shape: Body.Shape, offset: m.Vec2) !void {
    const size: f32 = switch (shape) {
        .circle => |circ| circ.radius / 2,
        .rectangle => |rect| rect.half_size.x() * 2,
    };
    for (0..count) |i| {
        const i_f32: f32 = @floatFromInt(i);
        const sign: f32 = if (i % 2 == 0) -1 else 1;
        _ = try world.createBody(Body.new(.dynamic, .{
            .position = m.Vec2.new(offset.x() + sign * size, offset.y() - i_f32 * size * 2),
            .shape = shape,
            .restitution = 0.8,
            .damping = 0.5,
        }));
    }
}

fn msFromNs(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
}

fn report(body_count: usize, total_ns: u64, timings: []u64) void {
    std.mem.sort(u64, timings, {}, std.sort.asc(u64));
    const n = timings.len;
    var sum: u64 = 0;
    for (timings) |t| sum += t;

    const mean = sum / n;
    const min = timings[0];
    const p50 = timings[n / 2];
    const p95 = timings[(n * 95) / 100];
    const p99 = timings[(n * 99) / 100];
    const max = timings[n - 1];
    const steps_per_s = @as(f64, @floatFromInt(n)) / (@as(f64, @floatFromInt(total_ns)) / 1e9);

    std.debug.print(
        \\
        \\phiz perf harness (headless)
        \\  bodies:          {d}
        \\  steps:           {d}  (timestep 1/60 s, {d} substeps)
        \\  total:           {d:.2} ms
        \\  per-step mean:   {d:.4} ms
        \\  per-step min:    {d:.4} ms
        \\  per-step p50:    {d:.4} ms
        \\  per-step p95:    {d:.4} ms
        \\  per-step p99:    {d:.4} ms
        \\  per-step max:    {d:.4} ms
        \\  throughput:      {d:.0} steps/s
        \\
    , .{
        body_count,
        n,
        PHYSICS_SUBSTEPS,
        msFromNs(total_ns),
        msFromNs(mean),
        msFromNs(min),
        msFromNs(p50),
        msFromNs(p95),
        msFromNs(p99),
        msFromNs(max),
        steps_per_s,
    });
}
