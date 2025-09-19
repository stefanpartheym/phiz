# φz (phiz)

> A very basic 2D physics engine written in the [Zig programming language](https://ziglang.org).

## Motivation

The goal is to provide a very basic physics solution for simple 2D games, eliminating the need to reimplement basic collision detection from scratch for every project. The main focus is on essential 2D collision detection and resolution without the complexity of a full physics simulation.

This project also serves as a learning exercise for me to understand the fundamentals of physics simulation.

The engine is **not** intended to solve complex collision scenarios. For a full fledged 2D physics engine, please use something like [box2d](https://box2d.org/).

## Constraints

- (Currently) only supports discrete collision detection (DCD).
- Collision detection only supports axis aligned bodies (no rotated bodies).
- Collision detection only supports rectangle and circle shapes.

## Features

The list of features I'm planning to implement:

- [x] AABB vs AABB collision detection (discrete)
- [x] Collision response for dynamic body vs static body collisions
- [x] Fully inelastic collision response for dynamic body vs dynamic body collisions
- [x] Circle vs AABB collision detection (discrete)
- [x] Circle vs circle collision detection (discrete)
- [ ] Broad phase collision detection (via spatial partitioning, quadtrees, etc.)
- [ ] Continuous collision detection for fast moving bodies

## Examples

Both examples use a fixed timestep of 1/60 seconds for physics simulation. This will provide consistent physics
simulation across frame rates and serves sort of a "best practice" on how to use the engine.

### Platformer

```sh
zig build run-platformer
```

This example demonstrates the use of gravity and a simple player controller for side-scrolling platformers.
Damping is used with two different values based on the player being on the ground or in the air.
This ensures the player will fall naturally due to gravity, but will gradually decelerate while being on the ground.

### Top-down

```sh
zig build run-topdown
```

This example demonstrates how to use the engine for top-down games (like RPG's, dungeon crawlers, survivor-likes, etc.),
that usually don't have gravity involved, since it's sort of a "top-down" view.
For the player a circle shape is used, which provides smooth sliding past corners.

## Resources

- [box2d.org](https://box2d.org/)
- https://github.com/erincatto/box2d-lite
- https://github.com/lumorsunil/zge
- https://github.com/silversquirl/phyz
