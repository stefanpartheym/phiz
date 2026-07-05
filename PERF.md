# zig 0.15.2 optimize=Debug

phiz perf harness (headless)
bodies: 485
steps: 600 (timestep 1/60 s, 4 substeps)
total: 4780.00 ms
per-step mean: 7.9665 ms
per-step min: 1.8848 ms
per-step p50: 8.1821 ms
per-step p95: 11.5065 ms
per-step p99: 14.0206 ms
per-step max: 26.0751 ms
throughput: 126 steps/s

# zig 0.15.2 optimize=ReleaseFast

phiz perf harness (headless)
bodies: 485
steps: 600 (timestep 1/60 s, 4 substeps)
total: 856.10 ms
per-step mean: 1.4268 ms
per-step min: 0.1457 ms
per-step p50: 1.4891 ms
per-step p95: 2.3471 ms
per-step p99: 2.4683 ms
per-step max: 3.0937 ms
throughput: 701 steps/s
