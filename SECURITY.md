# Security

ScaleForge is a local, single-user program. Its attack surface is the files
it reads: images, `.sfm` models, `.pth` files to convert, and JSON policy
files.

## Controls

- **No `unsafe`.** `unsafe_code = "forbid"` applies to the whole workspace.
  Parser bugs therefore become errors or panics, not memory corruption.
- **No third-party crates.** Every parser (JSON, zlib, PNG, JPEG, TIFF, ICC,
  EXIF, ZIP, pickle, `.sfm`) is our own code, reviewed here.
- **Limits before allocation** (`sf_core::Limits`):
  - image dimension, pixel count and decoded bytes;
  - ICC and metadata size;
  - JSON size and depth;
  - tensor count and size;
  - model file size.

  Decompression output is bounded. ZIP64 is refused.
- **Model files carry data only.** `.sfm` holds a graph of whitelisted
  operators and checksummed tensors; there is no code, and no plugin loading.
- **Pickle.** `.pth` conversion uses a restricted interpreter:
  - it never imports or calls anything;
  - it accepts only the globals needed to rebuild tensors (a fixed
    whitelist);
  - it rejects every other opcode or global, and a test proves that an
    `os.system` payload is refused;
  - it has an operation limit.
- **Paths.**
  - Outputs are written atomically (temporary file, then rename).
  - An existing file is never replaced without `--overwrite`.
  - The output may not be the input.
  - Batch mode skips symbolic links and writes only inside the chosen output
    directory.
- **No network access.** ScaleForge never downloads anything.

## Testing

- Unit tests and hand-built malformed files for every parser.
- 30,000 mutated-input cases for the JSON parser.
- Differential checks were run locally against independent decoders (see
  CHANGELOG).
- **Not done yet:** coverage-guided fuzzing campaigns (these need a nightly
  toolchain and `cargo-fuzz`).

## Reporting

This is a personal project. Record problems as issues in the repository.
