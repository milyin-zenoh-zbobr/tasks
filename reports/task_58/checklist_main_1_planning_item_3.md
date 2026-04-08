After changing `Option<T>` → `TomlOption<T>` in Toml structs, some consumer code may need updates.

**What:** Search for code that directly accesses fields on the Toml structs (outside of merge and build logic). This includes:
- Pattern matches on `Some(v)` / `None` for Toml struct fields
- `.unwrap_or()`, `.map()`, `.as_ref()` calls on Toml fields
- Direct field access in tests or utilities

**How:** The `TomlOption` type should provide an Option-compatible API (`as_option()`, `into_option()`, `is_some()`), so most fixes are mechanical: `.as_ref()` → `.as_option()`, `Some(v)` → `TomlOption::Value(v)`, etc.

**Why:** Minimize breakage from the type change. The goal is that final `*Config` structs still use `Option<T>`, so only code that touches `*Toml` intermediates needs updating.

**Scope:** This should be a small set of call sites. Compile the project and fix any remaining type errors.