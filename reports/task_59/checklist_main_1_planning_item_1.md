Verify the implementation compiles and doesn't break anything:

1. `cargo build -p zenoh --features internal` — confirms the new constructor compiles without shared-memory
2. `cargo build -p zenoh --features internal,shared-memory` — confirms the `is_shm` parameter variant compiles
3. `cargo test -p zenoh` — confirms existing tests still pass

These checks ensure the feature gate and conditional compilation are correctly applied.