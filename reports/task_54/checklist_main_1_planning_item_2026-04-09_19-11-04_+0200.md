Update all call sites that access data directly on event types:

**`tests/connectivity_test.go`**:
- For `TransportEvent`: change `evt.ZId()` → `evt.Transport().ZId()`, `evt.WhatAmI()` → `evt.Transport().WhatAmI()`, `evt.IsMulticast()` → `evt.Transport().IsMulticast()`, `evt.IsShm()` → `evt.Transport().IsShm()`, `evt.IsQos()` → `evt.Transport().IsQos()`. Affected tests: `TestTransportEventsListener`, `TestTransportEventsListenerWithHistory`, `TestBackgroundTransportEventsListenerWithHistory`, `TestTransportEventAccessors`.
- For `LinkEvent`: change `evt.ZId()` → `evt.Link().ZId()`, `evt.Src()` → `evt.Link().Src()`, `evt.Dst()` → `evt.Link().Dst()`, `evt.Mtu()` → `evt.Link().Mtu()`, `evt.IsStreamed()` → `evt.Link().IsStreamed()`, `evt.Interfaces()` → `evt.Link().Interfaces()`, `evt.Group()` → `evt.Link().Group()`. Affected tests: `TestLinkEventsListener`, `TestLinkEventsListenerWithHistory`, `TestBackgroundLinkEventsListenerWithHistoryAndFilter`, `TestLinkEventSnapshotFields`, `TestBackgroundLinkEventsListener`.

**`examples/z_info/z_info.go`**:
- In transport event callback: `evt.ZId()` → `evt.Transport().ZId()`
- In link event callback: `evt.ZId()` → `evt.Link().ZId()`, `evt.Src()` → `evt.Link().Src()`, `evt.Dst()` → `evt.Link().Dst()`