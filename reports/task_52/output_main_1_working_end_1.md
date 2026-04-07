All review findings addressed:

1. **Hoister boolean validation** — Now only consumes next token as `--logs` value when it's `true`/`false`, preventing positional arg theft
2. **Pre-subcommand normalization** — `--logs false` before subcommand is now joined into `--logs=false` so clap can parse it
3. **Type safety** — `Vec<String>` → `Vec<bool>`, invalid values rejected at parse time by clap