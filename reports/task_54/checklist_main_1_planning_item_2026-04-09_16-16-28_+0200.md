Update the options structs in `zenoh/link.go` to use `option.Option[Transport]` instead of `*Transport`.

**What to change**:
- `LinkEventsListenerOptions.Transport`: change type from `*Transport` to `option.Option[Transport]`
- `InfoLinksOptions.Transport`: change type from `*Transport` to `option.Option[Transport]`

**Why**: Using `option.Option[T]` is the idiomatic pattern in this codebase for optional values (consistent with how priorities and reliability are wrapped in LinkEvent). It makes the optionality explicit and avoids nil pointer issues.

**How `option.Option` is used**: The package is `github.com/BooleanCat/option`. Use `option.Some(transport)` to set a value, `option.None[Transport]()` for absent. Check with `.IsSome()` and unwrap with `.Unwrap()`.

**Impact**: The `toCOpts()` method for both options structs will need to check `opts.Transport.IsSome()` before constructing the C transport filter.