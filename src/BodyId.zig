const Self = @This();

pub const IndexType = usize;
pub const GenerationType = u16;

index: IndexType,
generation: GenerationType,

pub fn new(index: IndexType, generation: GenerationType) Self {
    return .{ .index = index, .generation = generation };
}
