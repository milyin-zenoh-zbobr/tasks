Create JNI callback interfaces in io.zenoh.jni.callbacks:
- JNITransportEventsCallback.kt: fun interface { fun run(kind: Int, zidBytes: ByteArray, whatAmI: Int, isQos: Boolean, isMulticast: Boolean) }
- JNILinkEventsCallback.kt: fun interface { fun run(kind: Int, zidBytes: ByteArray, src: String, dst: String, group: String?, mtu: Int, isStreamed: Boolean, interfaces: List<String>, authIdentifier: String?, priorityMin: Int, priorityMax: Int, reliability: Int) }
- JNITransportSnapshotCallback.kt: fun interface { fun run(zidBytes: ByteArray, whatAmI: Int, isQos: Boolean, isMulticast: Boolean) } (for one-shot snapshot queries)
- JNILinkSnapshotCallback.kt: fun interface { fun run(zidBytes: ByteArray, src: String, dst: String, group: String?, mtu: Int, isStreamed: Boolean, interfaces: List<String>, authIdentifier: String?, priorityMin: Int, priorityMax: Int, reliability: Int) }

Create JNI listener wrappers in io.zenoh.jni:
- JNITransportEventsListener.kt: holds ptr: Long, close() calls freePtrViaJNI(ptr)
- JNILinkEventsListener.kt: same pattern

Follow JNISampleMissListener.kt pattern exactly.
