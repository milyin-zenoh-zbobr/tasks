Create the following files in zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/:
- TransportEventsCallback.kt: @Unstable fun interface { fun run(event: TransportEvent) }
- TransportEventsHandler.kt: @Unstable interface with handle(event), receiver(): R, onClose()
- TransportEventsChannelHandler.kt: internal class wrapping Channel<TransportEvent>
- LinkEventsCallback.kt: same for LinkEvent
- LinkEventsHandler.kt: same for LinkEvent
- LinkEventsChannelHandler.kt: same for LinkEvent

Follow SampleMissCallback/Handler/ChannelHandler exactly.
