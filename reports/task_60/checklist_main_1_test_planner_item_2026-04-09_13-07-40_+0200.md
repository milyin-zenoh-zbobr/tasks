# Test: test_zc_internal_create_transport_drop

## Location
`tests/z_api_info.c`, inside `#if defined(Z_FEATURE_UNSTABLE_API)` block, called from `main()`.

## What to test
1. Create a transport via `zc_internal_create_transport()` with default options
2. Assert `z_internal_check(transport)` is true before drop
3. Call `z_drop(z_move(transport))`
4. Assert `z_internal_check(transport)` is false (gravestone / null state) after drop

## Why
Owned types in zenoh-c must transition to gravestone state after being moved/dropped. This validates the ownership semantics of the new constructor — no double-free, no use-after-free when callers follow the standard move-and-drop pattern.

## Template
```c
void test_zc_internal_create_transport_drop() {
    printf("=== Testing zc_internal_create_transport ownership/drop semantics ===\n");

    zc_internal_create_transport_options_t opts;
    zc_internal_create_transport_options_default(&opts);

    z_owned_transport_t transport;
    zc_internal_create_transport(&transport, &opts);

    assert(z_internal_check(transport) && "Transport must be valid before drop");
    z_drop(z_move(transport));
    assert(!z_internal_check(transport) && "Transport must be gravestone after drop");

    printf("PASS\n\n");
}
```
