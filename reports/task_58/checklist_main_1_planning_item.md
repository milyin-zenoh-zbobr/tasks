Create a new module `toml_option.rs` in `zbobr-utility/src/` and export it from `lib.rs`.

**What:** Define a three-state enum `TomlOption<T>` with variants `Absent`, `ExplicitNone`, and `Value(T)`.

**Behavior:**
- `Default` → `Absent`
- Custom `Deserialize`: use a visitor that intercepts float NaN (via `visit_f64`) to produce `ExplicitNone`, otherwise delegates to `T::deserialize` for `Value(T)`. For non-float fields, any value that parses as NaN in TOML (the literal `nan`) should also trigger `ExplicitNone`. Consider using an untagged helper approach similar to the pattern in `zbobr-utility/src/secret.rs` lines 84-113.
- `Serialize`: `Absent` → skip field (use `#[serde(skip_serializing_if = "...")]` or custom), `ExplicitNone` → serialize as `f64::NAN`, `Value(T)` → serialize T normally.
- Implement `MergeToml` trait (defined in `zbobr-utility/src/lib.rs` lines 19-28): merge(self=base, other=overlay) should return `other` if it's not `Absent`, else `self`. This replaces the `.or()` pattern used for `Option<T>`.
- Provide Option-compatible read API: `as_option(&self) -> Option<&T>`, `into_option(self) -> Option<T>`, `is_some()`, `is_none()` — so that conversion to final `*Config` structs (which use `Option<T>`) is straightforward.
- Implement `Clone`, `Debug`, `PartialEq` derives.

**Analog:** Follow the style and conventions of `secret.rs` for custom serde. Follow `MergeToml` trait pattern from `lib.rs`.