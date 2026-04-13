Create the following files in zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/:
- Transport.kt: @Unstable data class with zid: ZenohId, whatAmI: WhatAmI, isQos: Boolean, isMulticast: Boolean
- Link.kt: @Unstable data class with zid: ZenohId, src: String, dst: String, group: String?, mtu: Int, isStreamed: Boolean, interfaces: List<String>, authIdentifier: String?, priorityMin: Int?, priorityMax: Int?, reliability: Reliability?
- TransportEvent.kt: @Unstable data class with kind: SampleKind, transport: Transport
- LinkEvent.kt: @Unstable data class with kind: SampleKind, link: Link
- TransportEventsListener.kt: @Unstable class implementing SessionDeclaration+AutoCloseable, wrapping JNITransportEventsListener?
- LinkEventsListener.kt: same pattern wrapping JNILinkEventsListener?
