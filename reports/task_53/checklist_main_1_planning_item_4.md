## What
Extend `examples/z_info/z_info.go` to display transport and link information, and optionally monitor connectivity events, following the pattern from `z_info.c` in the zenoh-c PR.

## Why
The z_info example should showcase the full connectivity API, matching what the C example does.

## Changes
After the existing peers ZId output, add:

1. Print all transports: call `session.Transports()`, iterate and print each transport's properties (ZId, WhatAmI, IsQos, IsMulticast)

2. Print all links: call `session.Links(nil)`, iterate and print each link's properties (ZId, Src, Dst, Mtu, IsStreamed, Interfaces, etc.)

3. Set up event monitoring (following z_info.c pattern):
   - Declare a background transport events listener that prints "[Transport Event] Opened/Closed" 
   - Declare a background link events listener that prints "[Link Event] Added/Removed"
   - Wait for SIGINT/SIGTERM using `signal.Notify` on an `os.Signal` channel
   - Print "Exiting..." on signal

This mirrors the z_info.c example's unstable API section exactly.

## Analog
- `z_info.c` from zenoh-c PR — the C example this should mirror
- Current `examples/z_info/z_info.go` — the file being extended