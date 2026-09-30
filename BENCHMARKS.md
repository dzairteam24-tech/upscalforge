# Benchmarks

Only measured numbers appear here. Anything that cannot be measured is
`null`.

## Method

```sh
scaleforge benchmark --size 1024x768 --scale 2 --repeat 3 --json bench.json
```

The benchmark:

1. writes a synthetic RGB PNG;
2. runs the complete pipeline (decode → analysis → strategy → restore →
   enlarge → postprocess → encode → write) `--repeat` times;
3. reports the median and every run, per-stage medians, output megapixels
   per second, and CPU utilisation.

CPU utilisation is process CPU time divided by wall time, so 1.0 means one
fully busy core. It is read from `/proc/self/stat`, so it is Linux only.

## Results

### 2026-09-30 — classical engine, CPU

| | |
|---|---|
| Machine | Intel Xeon @ 2.80 GHz, 4 threads (cloud container) |
| Build | release, rustc 1.94.1 |
| Input | 1024x768 synthetic RGB → x2 (2048x1536), Faithful mode, PNG output |
| Total (median of 3) | **1855 ms** (runs: 1973, 1833, 1855) |
| Throughput | **1.70 output MP/s** |
| CPU utilisation | 1.37 |
| GPU utilisation | `null` (no GPU backend) |
| Model load | `null` (no model) |

Stage medians (ms):

| decode | analysis | strategy | restore | enlarge | postprocess | encode | write |
|--------|----------|----------|---------|---------|-------------|--------|-------|
| 29.5 | 57.4 | 0.01 | 5.4 | 251.2 | 569.2 | 920.6 | 5.6 |

### Observations

These are measurements, not yet optimisations:

- Encoding the PNG output (our own DEFLATE, single-threaded) takes half the
  time.
- Postprocessing (QC and consistency) is single-threaded.
- CPU utilisation of 1.37 on 4 threads shows that most stages do not run in
  parallel yet.

Phase 21 should start with these stages.

## Not measured

- **Model inference speed** (RRDBNet/SRVGG): no real weights were available
  in the development environment.
- **GPU**: the GPU backends are INCOMPLETE (Phase 8, waiting for hardware).
