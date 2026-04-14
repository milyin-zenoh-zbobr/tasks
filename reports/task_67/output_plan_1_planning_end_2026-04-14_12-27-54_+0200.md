Here is a summary of the plan I've designed:

## Plan: Replace zenoh-kotlin's Base Native Library with zenoh-java's

### Core Insight

After comparing both projects' JNI adapter classes, the `external fun` method signatures are **byte-for-byte identical** at the native boundary. JNI function names are derived from `Java_{package}_{class}_{method}` — since both use `io.zenoh.jni.*` with the same class and method names, zenoh-kotlin's existing JNI adapter Kotlin code works with zenoh-java's compiled `libzenoh_jni.so` **without any changes**.

### What Changes

| Component | Before | After |
|-----------|--------|-------|
| zenoh-kotlin public API | Own impl | **Unchanged** |
| zenoh-kotlin JNI adapters | Call own Rust lib | **Unchanged** (calls same-named functions, now in zenoh-java's lib) |
| Native library loaded | `libzenoh_jni.so` (zenoh-kotlin's, ~full) | `libzenoh_jni.so` (zenoh-java's) + `libzenoh_kotlin_ext.so` (ext-only) |
| Rust codebase | ~17 modules | Renamed `zenoh_kotlin_ext`, ~5 utility modules + `ext/` only |

### Key Decisions

1. **No Kotlin code changes** — the previous plan's fatal flaw (assuming API compatibility) is completely avoided
2. **Two native libraries** — zenoh-java's for base features, zenoh-kotlin's ext-only library for AdvancedPublisher/AdvancedSubscriber
3. **Session pointer cross-library use** — ext library receives session pointer from zenoh-java's library; safe because both use the same zenoh crate version (enforced by same-team release sync)
4. **No shading needed** — zenoh-java's public classes are naturally shadowed by zenoh-kotlin's on the classpath