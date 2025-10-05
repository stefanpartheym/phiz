const std = @import("std");
const tracy = @import("tracy");
const m = @import("m");
const Aabb = @import("./Aabb.zig");
const BodyId = @import("./BodyId.zig");

pub const BodyPair = struct {
    a: BodyId,
    b: BodyId,
    key: u64,

    /// Create a normalized BodyPair (smaller index first) to avoid duplicates.
    pub inline fn new(a: BodyId, b: BodyId) @This() {
        return if (a.index < b.index)
            @This(){
                .a = a,
                .b = b,
                .key = (@as(u64, a.index) << 32) | @as(u64, b.index),
            }
        else
            @This(){
                .a = b,
                .b = a,
                .key = (@as(u64, b.index) << 32) | @as(u64, a.index),
            };
    }
};

const GridCoord = struct {
    x: i32,
    y: i32,

    pub fn eql(self: GridCoord, other: GridCoord) bool {
        return self.x == other.x and self.y == other.y;
    }
};

const GridCoordContext = struct {
    pub fn hash(self: @This(), coord: GridCoord) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, coord.x);
        std.hash.autoHash(&hasher, coord.y);
        return hasher.final();
    }

    pub fn eql(self: @This(), a: GridCoord, b: GridCoord) bool {
        _ = self;
        return a.eql(b);
    }
};

const CellHashMap = std.HashMap(
    GridCoord,
    std.ArrayList(BodyId),
    GridCoordContext,
    std.hash_map.default_max_load_percentage,
);

/// Fast hash set specialized for u64 keys (pair IDs).
const FastPairSet = struct {
    buckets: []?u64,
    capacity: usize,
    count: usize,
    allocator: std.mem.Allocator,

    const EMPTY: ?u64 = null;
    const LOAD_FACTOR = 0.75;

    // Golden ratio constant for optimal hash distribution
    // This is 2^64 * (golden_ratio - 1) = 2^64 / golden_ratio
    const GOLDEN_RATIO_HASH: u64 = 0x9e3779b97f4a7c15;

    fn init(allocator: std.mem.Allocator) FastPairSet {
        return FastPairSet{
            .buckets = &[_]?u64{},
            .capacity = 0,
            .count = 0,
            .allocator = allocator,
        };
    }

    fn deinit(self: *FastPairSet) void {
        if (self.capacity > 0) {
            self.allocator.free(self.buckets);
        }
    }

    fn clearRetainingCapacity(self: *FastPairSet) void {
        @memset(self.buckets, EMPTY);
        self.count = 0;
    }

    fn ensureTotalCapacity(self: *FastPairSet, new_capacity: usize) !void {
        if (new_capacity == 0) return;
        const new_capacity_f32: f32 = @floatFromInt(new_capacity);
        const size_needed = @max(1, @as(u32, @intFromFloat(new_capacity_f32 / LOAD_FACTOR)));
        const target_capacity = @max(16, std.math.ceilPowerOfTwo(u32, size_needed) catch unreachable);

        if (target_capacity <= self.capacity) return;

        const old_buckets = self.buckets;
        const old_capacity = self.capacity;

        self.buckets = try self.allocator.alloc(?u64, target_capacity);
        self.capacity = target_capacity;
        @memset(self.buckets, EMPTY);
        self.count = 0;

        // Rehash existing elements
        for (old_buckets[0..old_capacity]) |maybe_key| {
            if (maybe_key) |key| {
                _ = self.insertAssumeCapacity(key);
            }
        }

        if (old_capacity > 0) {
            self.allocator.free(old_buckets);
        }
    }

    inline fn hash(key: u64) u32 {
        // SplitMix64-inspired hash function for better distribution.
        var x = key;
        x ^= x >> 32; // Mix upper/lower 32 bits
        x *%= GOLDEN_RATIO_HASH; // Multiply by golden ratio for optimal spread
        x ^= x >> 32; // Final mixing for avalanche effect
        return @truncate(x); // Return lower 32 bits
    }

    fn insertAssumeCapacity(self: *FastPairSet, key: u64) bool {
        const mask = self.capacity - 1;
        var idx = FastPairSet.hash(key) & mask;

        while (true) {
            if (self.buckets[idx] == EMPTY) {
                self.buckets[idx] = key;
                self.count += 1;
                return false; // Not found existing
            } else if (self.buckets[idx] == key) {
                return true; // Found existing
            }
            idx = (idx + 1) & mask; // Linear probing
        }
    }
};

const Self = @This();

cell_size: f32,
cells: CellHashMap,
allocator: std.mem.Allocator,
pairs: std.ArrayList(BodyPair),
processed_pairs: FastPairSet,
non_empty_cells: std.ArrayList(*std.ArrayList(BodyId)),
// Incremental update tracking
body_positions: std.ArrayList(m.Vec2),
body_cells: std.ArrayList(std.ArrayList(GridCoord)),
// Memory pool for reduced allocations
cell_pool: std.ArrayList(std.ArrayList(BodyId)),
coord_pool: std.ArrayList(std.ArrayList(GridCoord)),

pub fn init(allocator: std.mem.Allocator, cell_size: f32) Self {
    return Self{
        .cell_size = cell_size,
        .cells = CellHashMap.init(allocator),
        .allocator = allocator,
        .pairs = std.ArrayList(BodyPair){},
        .processed_pairs = FastPairSet.init(allocator),
        .non_empty_cells = std.ArrayList(*std.ArrayList(BodyId)){},
        .body_positions = std.ArrayList(m.Vec2){},
        .body_cells = std.ArrayList(std.ArrayList(GridCoord)){},
        .cell_pool = std.ArrayList(std.ArrayList(BodyId)){},
        .coord_pool = std.ArrayList(std.ArrayList(GridCoord)){},
    };
}

pub fn deinit(self: *Self) void {
    var iterator = self.cells.iterator();
    while (iterator.next()) |entry| {
        entry.value_ptr.deinit(self.allocator);
    }
    self.cells.deinit();
    self.pairs.deinit(self.allocator);
    self.processed_pairs.deinit();
    self.non_empty_cells.deinit(self.allocator);
    self.body_positions.deinit(self.allocator);
    for (self.body_cells.items) |*cell_list| {
        cell_list.deinit(self.allocator);
    }
    self.body_cells.deinit(self.allocator);
    for (self.cell_pool.items) |*cell_list| {
        cell_list.deinit(self.allocator);
    }
    self.cell_pool.deinit(self.allocator);
    for (self.coord_pool.items) |*coord_list| {
        coord_list.deinit(self.allocator);
    }
    self.coord_pool.deinit(self.allocator);
}

pub fn clear(self: *Self) void {
    var iterator = self.cells.iterator();
    while (iterator.next()) |entry| {
        entry.value_ptr.clearRetainingCapacity();
    }
}

/// Inserts a body into the grid based on its AABB.
pub fn insert(self: *Self, body_id: BodyId, aabb: Aabb) !void {
    const cells = self.getOverlappingCells(aabb);
    // Insert into body all overlapping cells.
    var y = cells.min.y;
    while (y <= cells.max.y) : (y += 1) {
        var x = cells.min.x;
        while (x <= cells.max.x) : (x += 1) {
            const coord = GridCoord{ .x = x, .y = y };
            const result = try self.cells.getOrPut(coord);
            if (!result.found_existing) {
                result.value_ptr.* = std.ArrayList(BodyId){};
            }
            try result.value_ptr.append(self.allocator, body_id);
        }
    }
}

/// Initialize incremental tracking for a body count.
pub fn initIncrementalTracking(self: *Self, body_count: usize) !void {
    const zone = tracy.initZone(@src(), .{});
    defer zone.deinit();

    // Only grow, never shrink to avoid invalidating existing data
    if (body_count <= self.body_positions.items.len) return;

    const old_len = self.body_positions.items.len;
    try self.body_positions.resize(self.allocator, body_count);
    try self.body_cells.resize(self.allocator, body_count);

    // Initialize only new cell lists
    for (self.body_cells.items[old_len..]) |*cell_list| {
        cell_list.* = std.ArrayList(GridCoord){};
    }

    // Initialize only new positions to invalid values to force initial update
    for (self.body_positions.items[old_len..]) |*pos| {
        pos.* = m.Vec2.new(std.math.inf(f32), std.math.inf(f32));
    }
}

/// Remove a body from its current cells.
fn removeBodyFromCells(self: *Self, body_id: BodyId) void {
    if (body_id.index >= self.body_cells.items.len) return;

    const cell_coords = &self.body_cells.items[body_id.index];
    for (cell_coords.items) |coord| {
        if (self.cells.getPtr(coord)) |cell_bodies| {
            // Remove body from this cell
            var i: usize = 0;
            while (i < cell_bodies.items.len) {
                if (cell_bodies.items[i].index == body_id.index) {
                    _ = cell_bodies.swapRemove(i);
                    break;
                }
                i += 1;
            }
        }
    }
    cell_coords.clearRetainingCapacity();
}

/// Insert body into new cells and track them.
fn insertBodyIntoCells(self: *Self, body_id: BodyId, aabb: Aabb) !void {
    const cells = self.getOverlappingCells(aabb);

    if (body_id.index >= self.body_cells.items.len) return;
    const cell_coords = &self.body_cells.items[body_id.index];

    var y = cells.min.y;
    while (y <= cells.max.y) : (y += 1) {
        var x = cells.min.x;
        while (x <= cells.max.x) : (x += 1) {
            const coord = GridCoord{ .x = x, .y = y };

            // Track this cell for the body
            try cell_coords.append(self.allocator, coord);

            // Add body to the cell
            const result = try self.cells.getOrPut(coord);
            if (!result.found_existing) {
                result.value_ptr.* = std.ArrayList(BodyId){};
            }
            try result.value_ptr.append(self.allocator, body_id);
        }
    }
}

/// Remove a body completely from the spatial grid.
pub fn removeBody(self: *Self, body_id: BodyId) void {
    // Remove from all cells it currently occupies
    self.removeBodyFromCells(body_id);

    // Mark position as invalid so it will be treated as "first time" if re-added
    if (body_id.index < self.body_positions.items.len) {
        self.body_positions.items[body_id.index] = m.Vec2.new(std.math.inf(f32), std.math.inf(f32));
    }
}

/// Update a body's position.
pub fn updateBody(self: *Self, body_id: BodyId, aabb: Aabb) !void {
    if (body_id.index >= self.body_positions.items.len) return;

    const current_center = aabb.getCenter();
    const last_position = &self.body_positions.items[body_id.index];

    // Check if this is the first time the body appears, due to invalid (infinite) position.
    const is_first_time = std.math.isInf(last_position.x()) or std.math.isInf(last_position.y());

    if (is_first_time) {
        // First time: Just insert and update position.
        try self.insertBodyIntoCells(body_id, aabb);
        last_position.* = current_center;
    } else {
        // Check if body moved enough to warrant an update.
        const movement = current_center.sub(last_position.*);
        const movement_threshold = self.cell_size * 0.1; // 10% of cell size

        if (@abs(movement.x()) > movement_threshold or @abs(movement.y()) > movement_threshold) {
            // Remove from old cells
            self.removeBodyFromCells(body_id);
            // Insert into new cells
            try self.insertBodyIntoCells(body_id, aabb);
            // Update cached position
            last_position.* = current_center;
        }
    }
}

/// Returns a list of potentially colliding body pairs.
pub fn getPairs(self: *Self) ![]const BodyPair {
    const zone = tracy.initZone(@src(), .{});
    defer zone.deinit();

    self.pairs.clearRetainingCapacity();
    self.processed_pairs.clearRetainingCapacity();
    self.non_empty_cells.clearRetainingCapacity();

    // Single pass: collect non-empty cells and estimate pairs
    var estimated_pairs: usize = 0;
    var iterator = self.cells.iterator();
    while (iterator.next()) |entry| {
        const body_count = entry.value_ptr.items.len;
        if (body_count > 1) {
            estimated_pairs += (body_count * (body_count - 1)) / 2;
            try self.non_empty_cells.append(self.allocator, entry.value_ptr);
        }
    }

    // Pre-allocate containers with estimated capacity
    try self.pairs.ensureTotalCapacity(self.allocator, estimated_pairs);
    try self.processed_pairs.ensureTotalCapacity(@intCast(estimated_pairs));

    // Process pairs from collected cells
    for (self.non_empty_cells.items) |body_list| {
        const body_count = body_list.items.len;
        if (body_count <= 8) {
            // Small cell: use optimized unrolled loops
            self.processSmallCell(body_list.items);
        } else {
            // Large cell: use vectorized approach
            try self.processLargeCell(body_list.items);
        }
    }

    return self.pairs.items;
}

/// Converts world position to grid coordinate.
fn worldToGrid(self: Self, pos: m.Vec2) GridCoord {
    return GridCoord{
        .x = @intFromFloat(@floor(pos.x() / self.cell_size)),
        .y = @intFromFloat(@floor(pos.y() / self.cell_size)),
    };
}

/// Gets the grid cells that an AABB overlaps.
fn getOverlappingCells(self: Self, aabb: Aabb) struct { min: GridCoord, max: GridCoord } {
    const min_coord = self.worldToGrid(aabb.min);
    const max_coord = self.worldToGrid(aabb.max);
    return .{ .min = min_coord, .max = max_coord };
}

/// Optimized processing for small cells (<= 8 bodies) using unrolled loops.
inline fn processSmallCell(self: *Self, bodies: []const BodyId) void {
    const len = bodies.len;
    comptime var i: usize = 0;
    inline while (i < 8) : (i += 1) {
        if (i >= len) break;
        comptime var j: usize = i + 1;
        inline while (j < 8) : (j += 1) {
            if (j >= len) break;
            const pair = BodyPair.new(bodies[i], bodies[j]);
            const found_existing = self.processed_pairs.insertAssumeCapacity(pair.key);
            if (!found_existing) {
                self.pairs.appendAssumeCapacity(pair);
            }
        }
    }
}

/// Optimized processing for large cells using batched operations.
fn processLargeCell(self: *Self, bodies: []const BodyId) !void {
    // Process in chunks of 4 for better cache performance
    const chunk_size = 4;
    var i: usize = 0;

    while (i < bodies.len) {
        const end_i = @min(i + chunk_size, bodies.len);
        var j = i + 1;

        while (j < bodies.len) {
            const end_j = @min(j + chunk_size, bodies.len);

            // Process chunk i against chunk j
            for (bodies[i..end_i]) |body_a| {
                for (bodies[j..end_j]) |body_b| {
                    const pair = BodyPair.new(body_a, body_b);
                    const found_existing = self.processed_pairs.insertAssumeCapacity(pair.key);
                    if (!found_existing) {
                        self.pairs.appendAssumeCapacity(pair);
                    }
                }
            }
            j = end_j;
        }

        // Process within chunk i
        for (bodies[i..end_i], 0..) |body_a, idx_a| {
            for (bodies[i + idx_a + 1 .. end_i]) |body_b| {
                const pair = BodyPair.new(body_a, body_b);
                const found_existing = self.processed_pairs.insertAssumeCapacity(pair.key);
                if (!found_existing) {
                    self.pairs.appendAssumeCapacity(pair);
                }
            }
        }
        i = end_i;
    }
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const SpatialHashGrid = Self;

test "SpatialHashGrid.worldToGrid: Should convert world coordinates to grid coordinates" {
    const grid = SpatialHashGrid.init(std.testing.allocator, 10);

    try std.testing.expectEqual(GridCoord{ .x = 0, .y = 0 }, grid.worldToGrid(m.Vec2.new(0, 0)));
    try std.testing.expectEqual(GridCoord{ .x = 1, .y = 1 }, grid.worldToGrid(m.Vec2.new(10, 10)));
    try std.testing.expectEqual(GridCoord{ .x = -1, .y = -1 }, grid.worldToGrid(m.Vec2.new(-5, -5)));
    try std.testing.expectEqual(GridCoord{ .x = 2, .y = 3 }, grid.worldToGrid(m.Vec2.new(25, 35)));
}

test "SpatialHashGrid.getOverlappingCells: Should return correct cell range for AABB" {
    const grid = SpatialHashGrid.init(std.testing.allocator, 10);

    const aabb = Aabb.new(m.Vec2.new(5, 5), m.Vec2.new(25, 15));
    const cells = grid.getOverlappingCells(aabb);

    try std.testing.expectEqual(GridCoord{ .x = 0, .y = 0 }, cells.min);
    try std.testing.expectEqual(GridCoord{ .x = 2, .y = 1 }, cells.max);
}

test "SpatialHashGrid.insert: Should insert body into correct cells" {
    var grid = SpatialHashGrid.init(std.testing.allocator, 10);
    defer grid.deinit();

    const body_id = BodyId.new(0, 0);
    const aabb = Aabb.new(m.Vec2.new(5, 5), m.Vec2.new(15, 15));

    try grid.insert(body_id, aabb);

    // Body should be in 4 cells: (0,0), (0,1), (1,0), (1,1)
    try std.testing.expectEqual(@as(usize, 4), grid.cells.count());

    // Check that body is in the expected cells
    const expected_coords = [_]GridCoord{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 1 },
        .{ .x = 1, .y = 0 },
        .{ .x = 1, .y = 1 },
    };

    for (expected_coords) |coord| {
        const cell = grid.cells.get(coord);
        try std.testing.expect(cell != null);
        try std.testing.expectEqual(@as(usize, 1), cell.?.items.len);
        try std.testing.expectEqual(body_id.index, cell.?.items[0].index);
    }
}

test "SpatialHashGrid.getPairs: Should return correct pairs" {
    var grid = SpatialHashGrid.init(std.testing.allocator, 10);
    defer grid.deinit();

    const body_a = BodyId.new(0, 0);
    const body_b = BodyId.new(1, 0);
    const body_c = BodyId.new(2, 0);

    // Bodies A and B overlap in same cell
    try grid.insert(body_a, Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(5, 5)));
    try grid.insert(body_b, Aabb.new(m.Vec2.new(2, 2), m.Vec2.new(7, 7)));

    // Body C is in a different cell
    try grid.insert(body_c, Aabb.new(m.Vec2.new(20, 20), m.Vec2.new(25, 25)));

    const pairs = try grid.getPairs();

    // Should only have one pair: A-B
    try std.testing.expectEqual(@as(usize, 1), pairs.len);
    const pair = pairs[0];
    try std.testing.expect((pair.a.index == 0 and pair.b.index == 1) or (pair.a.index == 1 and pair.b.index == 0));
}

test "SpatialHashGrid.clear: Should clear all cells but keep memory" {
    var grid = SpatialHashGrid.init(std.testing.allocator, 10);
    defer grid.deinit();

    try grid.insert(BodyId.new(0, 0), Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(5, 5)));
    try grid.insert(BodyId.new(1, 0), Aabb.new(m.Vec2.new(10, 10), m.Vec2.new(15, 15)));

    try std.testing.expect(grid.cells.count() > 0);

    grid.clear();

    // Cells should still exist but be empty
    var iterator = grid.cells.iterator();
    while (iterator.next()) |entry| {
        try std.testing.expectEqual(@as(usize, 0), entry.value_ptr.items.len);
    }
}
