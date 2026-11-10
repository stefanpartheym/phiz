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

# zig 0.16.0 optimize=Debug

phiz perf harness (headless)
bodies: 485
steps: 600 (timestep 1/60 s, 4 substeps)
total: 7728.78 ms
per-step mean: 12.8811 ms
per-step min: 3.2001 ms
per-step p50: 13.1521 ms
per-step p95: 19.1817 ms
per-step p99: 20.0462 ms
per-step max: 21.9968 ms
throughput: 78 steps/s

# zig 0.16.0 optimize=ReleaseFast

phiz perf harness (headless)
bodies: 485
steps: 600 (timestep 1/60 s, 4 substeps)
total: 1053.14 ms
per-step mean: 1.7552 ms
per-step min: 0.2127 ms
per-step p50: 2.0628 ms
per-step p95: 2.8863 ms
per-step p99: 3.0707 ms
per-step max: 3.9551 ms
throughput: 570 steps/s

# zig 0.17.1 optimize=Debug

phiz perf harness (headless)
bodies: 485
steps: 600 (timestep 1/60 s, 4 substeps)
total: 7825.76 ms
per-step mean: 13.0426 ms
per-step min: 3.2437 ms
per-step p50: 13.6314 ms
per-step p95: 19.4504 ms
per-step p99: 19.7562 ms
per-step max: 20.4906 ms
throughput: 77 steps/s

# zig 0.17.1 optimize=ReleaseFast

phiz perf harness (headless)
bodies: 485
steps: 600 (timestep 1/60 s, 4 substeps)
total: 993.94 ms
per-step mean: 1.6565 ms
per-step min: 0.1849 ms
per-step p50: 1.6459 ms
per-step p95: 2.7943 ms
per-step p99: 2.8958 ms
per-step max: 3.2913 ms
throughput: 604 steps/s
