#/bin/sh
# get current script directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# load .env file unless user has specified the BASH_ENV variable
[ -z "$BASH_ENV" ] && [ -f "$DIR/.env" ] && { set -a; source "$DIR/.env"; set +a; }
# run zbobr with the provided arguments
cargo run --manifest-path ../zbobr/Cargo.toml -- $@
