#/bin/sh
# get current script directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cargo run --manifest-path ../zbobr/Cargo.toml -- $@
