Plan finalized and sent to implementation. The two checklist items are:

1. **Cargo.toml** — comment out the four `eclipse-zenoh/zenoh.git` dependency lines and add equivalents pointing to `milyin-zenoh-zbobr/zenoh.git` on `zbobr_fix-59-implement-transport-from-fields-constructor`
2. **src/info.rs** — add `zc_internal_transport_from_fields` after `z_internal_transport_null` (~line 230), gated by `#[cfg(feature = "unstable")]`, following the existing MaybeUninit write pattern and `z_whatami_t` → `WhatAmI` conversion