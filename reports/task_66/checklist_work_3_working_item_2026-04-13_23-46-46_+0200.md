Create connectivity.rs implementing:
- Java_io_zenoh_jni_JNISession_getTransportsViaJNI: iterates transports, calls callback for each
- Java_io_zenoh_jni_JNISession_getLinksViaJNI: iterates links (optionally filtered), calls callback for each
- Java_io_zenoh_jni_JNISession_declareTransportEventsListenerViaJNI: GlobalRef+JavaVM callback, returns Arc<TransportEventsListener<()>> raw ptr
- Java_io_zenoh_jni_JNISession_declareBackgroundTransportEventsListenerViaJNI: same but background
- Java_io_zenoh_jni_JNISession_declareLinkEventsListenerViaJNI: with optional transport filter
- Java_io_zenoh_jni_JNISession_declareBackgroundLinkEventsListenerViaJNI: background
- Java_io_zenoh_jni_JNITransportEventsListener_freePtrViaJNI: Arc::from_raw to drop
- Java_io_zenoh_jni_JNILinkEventsListener_freePtrViaJNI: Arc::from_raw to drop

All functions require #[zenoh_macros::unstable] or equivalent (use feature "unstable" which is already enabled).
Transport filter: if zid != null, call Transport::new_from_fields to reconstruct; pass to .links().transport(t).

Add `mod connectivity;` to lib.rs.
Run cargo build to verify.
