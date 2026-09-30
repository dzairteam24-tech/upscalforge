# Contributing

ScaleForge is a personal project. These rules apply to any change:

1. **Original work only.** Do not copy or translate code, tests or
   documentation from other projects. External pretrained *weights* are
   allowed only under ADR-0015, labelled `external`.
2. **No new dependencies** without an audit entry in `DEPENDENCIES.md` and the
   owner's approval. Nothing is installed automatically.
3. **Honesty.**
   - Label unfinished work INCOMPLETE.
   - Never publish benchmark numbers that were not measured.
   - Never present a placeholder as working.
4. **Gate before every commit:**
   ```sh
   cargo fmt --check
   cargo clippy --workspace --all-targets -- -D warnings
   cargo test --workspace --release
   ```
5. **Significant decisions** get an ADR in `docs/adr/`.
6. **Each change updates** `CHANGELOG.md`, and the docs it affects.

See `DEVELOPMENT.md` for the repository layout and test conventions.
