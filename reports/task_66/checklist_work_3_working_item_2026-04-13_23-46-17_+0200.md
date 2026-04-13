Add to JNISession.kt:
- External declarations for all 6 JNI functions
- Kotlin wrapper methods that wire callbacks and construct data objects:
  - getTransports(): iterates via snapshot callback, constructs Transport list
  - getLinks(transport?): iterates via snapshot callback, constructs Link list
  - declareTransportEventsListener(callback, onClose, history): wires JNITransportEventsCallback, returns TransportEventsListener
  - declareBackgroundTransportEventsListener(callback, onClose, history): returns Unit
  - declareLinkEventsListener(callback, onClose, history, transport?): with transport filter
  - declareBackgroundLinkEventsListener(callback, onClose, history, transport?): returns Unit

Use callback-per-item approach for snapshots (like scout), GlobalRef+onClose approach for event listeners.
Transport filter passed as zid: ByteArray?, whatAmI: Int, isQos: Boolean, isMulticast: Boolean (null zid = no filter).
