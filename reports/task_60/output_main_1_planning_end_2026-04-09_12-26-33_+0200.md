The plan is to:

1. **Add `zc_internal_create_transport_options_t` struct** in `src/info.rs` — `#[repr(C)]`, all fields inline, with `is_shm` wrapped in `#[cfg(feature = "shared-memory")]`. Plus a `_default` constructor.

2. **Rename `zc_internal_transport_from_fields` → `zc_internal_create_transport`** — takes `&zc_internal_create_transport_options_t` instead of individual params.

3. **Regenerate the header** — cbindgen correctly handles `#[cfg]` on struct fields (wraps them in `#ifdef Z_FEATURE_SHARED_MEMORY`), fixing the ABI mismatch from the previous approach.

Analog: `z_publisher_options_t` in `src/publisher.rs` uses the exact same `#[cfg]`-gated struct field pattern.