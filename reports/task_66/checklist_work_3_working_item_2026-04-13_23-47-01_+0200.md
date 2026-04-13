Create zenoh-kotlin/src/commonTest/kotlin/io/zenoh/ConnectivityTest.kt with:
- testTransportsList: two peer sessions, assert transports() non-empty with peer ZID
- testLinksListNoFilter: two connected sessions, assert links() non-empty
- testLinksListWithFilter: use Transport from transports() as filter for links(transport)
- testTransportEventsListenerPutDelete: subscribe to events, connect second session (PUT), disconnect (DELETE)
- testTransportEventsHistory: connect peer first, then open listener with history=true, assert history PUT event
- testLinkEventsListenerPutDelete: same for link events
- testLinkEventsListenerWithTransportFilter: filter by Transport from transports() (not from LinkEvent)
- testBackgroundListeners: background variants fire correctly

Use Channel<TransportEvent>/<LinkEvent> for collecting events in tests.
Use unique ports (7465+) to avoid conflicts with other tests.
Run ./gradlew test --tests "io.zenoh.ConnectivityTest" to verify.
