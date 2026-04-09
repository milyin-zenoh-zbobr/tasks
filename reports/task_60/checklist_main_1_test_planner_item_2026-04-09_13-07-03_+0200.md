# Test: zc_internal_create_transport_options_default

## Location
`tests/z_api_info.c`, inside `#if defined(Z_FEATURE_UNSTABLE_API)` block, called from `main()`.

## What to test
Call `zc_internal_create_transport_options_default()` and assert:
- `opts.whatami == Z_WHATAMI_CLIENT`
- `opts.is_qos == false`
- `opts.is_multicast == false`
- `#if defined(Z_FEATURE_SHARED_MEMORY)`: `opts.is_shm == false`

## Why
Validates the documented defaults for the options struct. If defaults change silently, callers depending on them will be broken.

## Template
```c
void test_zc_internal_create_transport_options_default() {
    printf("=== Testing zc_internal_create_transport_options_default ===\n");
    zc_internal_create_transport_options_t opts;
    zc_internal_create_transport_options_default(&opts);
    assert(opts.whatami == Z_WHATAMI_CLIENT && "Default whatami should be CLIENT");
    assert(opts.is_qos == false && "Default is_qos should be false");
    assert(opts.is_multicast == false && "Default is_multicast should be false");
#if defined(Z_FEATURE_SHARED_MEMORY)
    assert(opts.is_shm == false && "Default is_shm should be false");
#endif
    printf("PASS\n\n");
}
```
