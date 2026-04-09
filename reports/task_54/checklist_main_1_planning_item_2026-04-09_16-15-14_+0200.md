Update the zenoh-c submodule to point to the fork that provides `zc_internal_create_transport`.

**What to change**: In `.gitmodules`, update the submodule URL from the official `eclipse-zenoh/zenoh-c` to `https://github.com/milyin-zenoh-zbobr/zenoh-c.git` (or the correct fork URL) and set branch to `zbobr_fix-60-transport-from-fields`. Run `git submodule update --init --remote` to pull the new content.

**Why**: The `zc_internal_create_transport` function needed for filtering is in this branch (zenoh-c PR #1265) and not yet in the official zenoh-c main.

**Easy rollback**: Add a comment in `.gitmodules` with the original URL (`https://github.com/eclipse-zenoh/zenoh-c.git`) so it's trivial to switch back. The CI `ci.yml` may also reference zenoh-c — update it to avoid breaking the build.

**Verification**: After updating, confirm that `zenoh-c/include/zenoh_ext.h` (or wherever `zc_internal_create_transport` is declared) contains that function declaration.