# Test: test_zc_internal_create_transport_all_whatami

## Location
`tests/z_api_info.c`, inside `#if defined(Z_FEATURE_UNSTABLE_API)` block, called from `main()`.

## What to test
For each of the three `z_whatami_t` values (Z_WHATAMI_CLIENT, Z_WHATAMI_PEER, Z_WHATAMI_ROUTER):
1. Construct a known `z_id_t` (e.g. all zeros with last byte set to the loop index)
2. Build `zc_internal_create_transport_options_t` with that ZID, the current whatami, `is_qos=true`, `is_multicast=false`
3. Call `zc_internal_create_transport()` → `z_owned_transport_t`
4. Assert `z_internal_check(transport)` is true (valid, not gravestone)
5. Assert `z_transport_zid(z_loan(transport))` matches the ZID passed in
6. Assert `z_transport_whatami(z_loan(transport))` equals the whatami passed in
7. Assert `z_transport_is_qos(z_loan(transport))` is true
8. Assert `z_transport_is_multicast(z_loan(transport))` is false
9. `z_drop(z_move(transport))`

## Why
Validates the core behavioural contract of the new constructor: field values survive the Rust→C boundary correctly for all valid enum variants. The exhaustive `match` in the Rust implementation means only these three variants are reachable; this test confirms each path produces the right observable state.

## Template
```c
void test_zc_internal_create_transport_all_whatami() {
    printf("=== Testing zc_internal_create_transport for all whatami variants ===\n");

    z_whatami_t variants[] = {Z_WHATAMI_CLIENT, Z_WHATAMI_PEER, Z_WHATAMI_ROUTER};
    const char* names[] = {"CLIENT", "PEER", "ROUTER"};

    for (int i = 0; i < 3; i++) {
        z_id_t zid = {0};
        zid.id[15] = (uint8_t)(i + 1);

        zc_internal_create_transport_options_t opts;
        zc_internal_create_transport_options_default(&opts);
        opts.zid = zid;
        opts.whatami = variants[i];
        opts.is_qos = true;
        opts.is_multicast = false;

        z_owned_transport_t transport;
        zc_internal_create_transport(&transport, &opts);

        assert(z_internal_check(transport) && "Transport must be valid after creation");

        z_id_t got_zid = z_transport_zid(z_loan(transport));
        assert(memcmp(&got_zid, &zid, sizeof(z_id_t)) == 0 && "ZID round-trip failed");

        z_whatami_t got_whatami = z_transport_whatami(z_loan(transport));
        assert(got_whatami == variants[i] && "whatami round-trip failed");

        assert(z_transport_is_qos(z_loan(transport)) == true && "is_qos round-trip failed");
        assert(z_transport_is_multicast(z_loan(transport)) == false && "is_multicast round-trip failed");

        z_drop(z_move(transport));
        printf("PASS: %s\n", names[i]);
    }
    printf("\n");
}
```
