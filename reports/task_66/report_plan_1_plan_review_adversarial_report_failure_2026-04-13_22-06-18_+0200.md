The revised plan fixes the earlier Kotlin API-shape problems and is much closer to implementation-ready, but I would still send it back for revision because two architectural assumptions are unsound.

## What is good

- Modeling the Kotlin listener surface after the existing matching/sample-miss APIs is correct for this repo.
- Adding callback/handler/channel overloads plus background variants is consistent with the current Kotlin API.
- Using structured JNI data for `interfaces` and using `.background().wait()` on the Rust side matches the existing native patterns.
- Covering `history` and transport-filtered link APIs is the right upstream scope.

## Blocking issues

### 1. The plan’s transport-filter design is not safe

The plan says to pass only `transport.zid.bytes` through JNI for:
- `links(transport)`
- link event listener transport filtering

and then recover the Rust `Transport` by scanning `session.info().transports()` for a matching zid.

That is not a sound identity scheme.

Upstream zenoh explicitly allows **multiple transports to the same peer**. In `zenoh/src/api/info.rs`, the `Transport` docs say:
> "Multiple transports to the same peer can exist. At this moment it's possible to have both a unicast and a multicast transport to the same peer."

So a zid-only filter can pick the wrong transport whenever more than one transport exists for the same remote node. This is especially relevant because the whole point of `links().transport(...)` and filtered link listeners is to preserve transport-level distinction.

The upstream session internals also keep the link-listener filter as an actual `Transport` object, not just a zid. And the Go binding analog requested by the issue converts a full transport snapshot back into a native transport for filtering (`Transport.toCPtr()`), rather than filtering by zid alone.

**What the plan should require instead:**
- Either carry enough transport identity across JNI to reconstruct the filter safely (at minimum not just zid; ideally the full snapshot used by the Go binding approach), or
- Create a native-side transport snapshot/wrapper that Kotlin can round-trip back for filter use.

Without that change, a worker could implement a seemingly working API that becomes wrong as soon as multiple transports share a zid.

### 2. `isShm` is planned as unconditional, but this repo does not enable the upstream feature that exposes it

The plan treats `Transport.isShm` as an always-present field in both Kotlin and JNI callbacks.

But upstream zenoh exposes `Transport.is_shm` behind `#[cfg(feature = "shared-memory")]` in `zenoh/src/api/info.rs`. In this repo, `zenoh-jni/Cargo.toml` depends on:
- `zenoh` with features `["unstable", "internal"]`
- `zenoh-ext` with features `["unstable", "internal"]`
- `default-features = false`

There is **no `shared-memory` feature enabled** here.

That means the plan currently assumes a field that upstream Rust does not expose in this repository’s current feature configuration. A worker following the plan could easily end up writing Rust that does not compile, or silently expanding the repo’s feature policy without the plan ever discussing that tradeoff.

**What the plan should require instead:**
- Either explicitly omit `isShm` from the Kotlin/JNI surface for now,
- or explicitly add and justify enabling the Rust `shared-memory` feature across the binding,
- or explicitly define a compatibility fallback and call out that it intentionally diverges from upstream feature-gated behavior.

Right now the plan does none of those.

## Secondary correction

The verification command `cd zenoh-jni && cargo build --features unstable` does not match this crate’s feature table. `zenoh-jni/Cargo.toml` does not define a local `unstable` feature; unstable is already enabled on the `zenoh` dependency. The verification section should be updated so it does not send the implementer to a failing command.

## Recommendation

Revise the plan before implementation. The overall API shape is now good, but the plan must:
1. Replace the zid-only transport filter design with a full, reconstructable transport identity approach aligned with the Go analog.
2. Resolve the `isShm` feature-gating mismatch explicitly.
3. Fix the verification command.

Once those are addressed, I would consider the plan ready.