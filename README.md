# φz (phiz)

> A very basic 2D physics engine written in the [Zig programming language](https://ziglang.org).

## Motivation

The goal is to provide a very basic physics solution for simple 2D games, eliminating the need to reimplement basic collision detection from scratch for every project. The main focus is on essential 2D collision detection and resolution without the complexity of a full physics simulation.

This project also serves as a learning exercise for me to understand the fundamentals of physics simulation.

The engine is **not** intended to solve complex collision scenarios. For a full fledged 2D physics engine, please use something like [box2d](https://box2d.org/).

## Constraints

- (Currently) only supports discrete collision detection (DCD).
- Collision detection only supports axis aligned bodies (no rotated bodies).
- Collision detection (currently) only supports rectangle shapes.

## Features

The list of features I'm planning to implement:

- [x] AABB vs AABB collision detection (discrete)
- [x] Collision response for dynamic body vs static body collisions
- [x] Fully inelastic collision response for dynamic body vs dynamic body collisions
- [ ] Circle vs AABB collision detection (discrete)
- [ ] Circle vs circle collision detection (discrete)
- [ ] Broad phase collision detection (via spatial partitioning, quadtrees, etc.)
- [ ] Continuous collision detection for fast moving bodies

## Examples

2D platformer:

```sh
zig build run-platformer

```

## Resources

- [box2d.org](https://box2d.org/)
- https://github.com/erincatto/box2d-lite
- https://github.com/lumorsunil/zge
- https://github.com/silversquirl/phyz
