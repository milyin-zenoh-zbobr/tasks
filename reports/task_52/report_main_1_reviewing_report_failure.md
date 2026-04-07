Review result: **changes are not ready to merge**.

Overall assessment:
- **`task select`** looks good. The planner chose an appropriate analog (`TaskSubcommand` variants like `Show`/`Delete`), and the implementation in `zbobr/src/commands.rs` follows the existing command style cleanly.
- **`--logs` optional boolean** has a correctness bug in the parser/hoisting path and uses a type that is broader than the domain requires.

## Findings

### 1. `--logs` space-separated values are not implemented correctly across the full CLI
**Files:**
- `zbobr/src/main.rs:42-64`
- `zbobr-dispatcher/src/cli.rs:217-225`

**Problem:**
The issue explicitly requires these forms to work:
- `--logs`
- `--logs true`
- `--logs false`
- `--logs=true`
- `--logs=false`

The current implementation only rewrites **post-subcommand** optional values into `--logs=<value>` inside `parse_cli`. Arguments that appear **before** the subcommand are copied through unchanged (`before_sub.push(arg.clone())` in the pre-subcommand path), while the clap definition has `require_equals = true`.

That means a command like:
- `zbobr --logs false task process --select`

is not normalized before clap sees it, so the advertised `--logs false` form is not actually supported in that common placement.

**Why this matters:**
The implementation claims support for `--logs false` / `--logs true`, but that support depends on where the option appears. That is a user-visible behavior bug.

**Suggested fix:**
Normalize optional-value globals consistently both before and after the subcommand, or remove `require_equals = true` if native space-separated parsing should be accepted everywhere.

---

### 2. The hoister consumes any non-flag token as a `--logs` value, which can steal positional arguments
**Files:**
- `zbobr-dispatcher/src/cli.rs:217-225`

**Problem:**
For optional-value globals, the hoister currently consumes the next token whenever it does not start with `-`:

```rust
} else if matches!(valence, ArgValence::OptionalValue)
    && i + 1 < raw_args.len()
    && !raw_args[i + 1].starts_with('-')
{
    before_sub.push(format!("{}={}", arg, raw_args[i + 1]));
    i += 2;
}
```

But the plan correctly identified the key risk here: `--logs` should only consume the next token if it is a valid boolean literal (`true`/`false`). The current logic will also consume unrelated positional arguments.

Example regression:
- `zbobr task show --logs 42`

This should parse as `task show 42` with logs enabled, but the hoister will rewrite it to `--logs=42` and remove `42` from the `show` subcommand.

**Why this matters:**
This breaks unrelated command parsing and makes the new global option unsafe when used after a subcommand.

**Suggested fix:**
Only consume the following token for `--logs` when it is a recognized boolean value. Otherwise hoist just `--logs` and leave the next token in the subcommand argument stream.

---

### 3. `logs: Vec<String>` is too weakly typed and silently accepts invalid boolean values
**Files:**
- `zbobr/src/main.rs:43-64`
- `zbobr-dispatcher/src/cli.rs:95`

**Problem:**
The new field type is `Vec<String>`, and `resolve_logs()` treats every value other than case-insensitive `"false"` as `true`:

```rust
fn resolve_logs(values: &[String]) -> bool {
    values
        .last()
        .map(|v| !v.eq_ignore_ascii_case("false"))
        .unwrap_or(false)
}
```

So these invalid inputs are accepted and interpreted as `true` instead of being rejected:
- `--logs=maybe`
- `--logs=0`
- `--logs=whatever`

This is both a correctness issue and a type-specificity issue. The domain is boolean; the parser should enforce that at parse time rather than relying on string matching afterward.

**Suggested fix:**
Use a boolean-typed collection (for example a typed parser / `Vec<bool>`-style approach) so clap rejects invalid values directly. That also removes the need for ad-hoc string resolution and makes the last-value-wins semantics type-safe.

## Analog consistency
- **Good:** `task select` matches the existing subcommand architecture and looks like a natural extension of the CLI.
- **Not good:** the `--logs` implementation does not fully follow the planner’s intended pattern. The plan explicitly called out that the hoister must check for valid boolean tokens before consuming them; the implementation instead consumes any non-flag token. The broader `String` type also weakens the contract compared with the boolean behavior the feature is meant to provide.

## Checklist status
All checklist items were already marked complete, but based on the findings above, the `--logs` item is not actually complete from a correctness perspective.