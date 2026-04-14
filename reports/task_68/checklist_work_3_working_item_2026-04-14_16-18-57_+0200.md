Add to session.rs:
1. New imports: PublisherBuilder, SubscriberBuilder, Callback from zenoh; OwnedObject from owned_object; SetJniSampleCallback from sample_callback; jdouble and zenoh-ext types under cfg(feature="zenoh-ext")
2. New JNI export: Java_io_zenoh_jni_JNISession_openSessionViaJNI (instance method variant)
3. New private helper: prepare_publisher_builder
4. New private helper: prepare_subscriber_builder
5. New JNI export: Java_io_zenoh_jni_JNISession_declareAdvancedSubscriberViaJNI (gated with zenoh-ext)
6. New JNI export: Java_io_zenoh_jni_JNISession_declareAdvancedPublisherViaJNI (gated with zenoh-ext)