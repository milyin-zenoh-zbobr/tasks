clang-format check failed with many -Wclang-format-violations across include/, tests/, and src/ files. Example (first lines):

(include/zenoh_memory.h:5:19) static inline void *z_malloc(size_t size) { return malloc(size); }
(include/zenoh_memory.h:6:19) static inline void *z_realloc(void *ptr, size_t size) { return realloc(ptr, size); }
... (many similar violations in tests/*.c and headers)

cargo clippy and cargo fmt were executed; see full CI-like output saved to temporary file on the runner:
/tmp/copilot-tool-output-1775733682849-88dme3.txt

To reproduce locally, run these commands from repository root (same as CI):
1) clang-format dry run:
   find include/ src/ tests/ examples/ -iname "*.h" -o -iname "*.c" | xargs clang-format -n -Werror

2) install rustfmt/clippy:
   rustup component add rustfmt clippy

3) cargo clippy:
   cargo clippy --all-targets --no-default-features --features unstable,shared-memory -- --deny warnings

4) cargo fmt check:
   cargo fmt --check -- --config "unstable_features=true,imports_granularity=Crate,group_imports=StdExternalCrate"

Full raw output captured at: /tmp/copilot-tool-output-1775733682849-88dme3.txt
