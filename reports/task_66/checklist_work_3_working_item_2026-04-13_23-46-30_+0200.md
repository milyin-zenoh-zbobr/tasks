Extend Session.kt with internal delegation methods:
- getTransports(): Result<List<Transport>> - delegates to jniSession
- getLinks(transport: Transport?): Result<List<Link>>
- declareTransportEventsListener(...): Result<TransportEventsListener> - registers in strongDeclarations
- declareBackgroundTransportEventsListener(...): Result<Unit>
- declareLinkEventsListener(...): Result<LinkEventsListener> - registers in strongDeclarations
- declareBackgroundLinkEventsListener(...): Result<Unit>

Extend SessionInfo.kt with @Unstable public API:
- transports(): Result<List<Transport>>
- links(transport: Transport? = null): Result<List<Link>>
- Transport event listeners: 6 overloads (3 foreground + 3 background) with history: Boolean = false
- Link event listeners: 6 overloads (3 foreground + 3 background) with transport: Transport? = null

Follow the pattern from existing AdvancedSubscriber.declareSampleMissListener.
Background listeners are NOT added to strongDeclarations.
