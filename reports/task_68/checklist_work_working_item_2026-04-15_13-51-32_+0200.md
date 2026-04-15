Create JNISession in zenoh-jni-runtime:
- `public class JNISession(val sessionPtr: Long)`
- Companion `fun open(configPtr: Long): JNISession` (takes Long, not Config)
- Keep `@JvmStatic` on openSessionViaJNI in companion
- Make all `private external fun` declarations `public external fun`
- Add declareAdvancedSubscriberViaJNI and declareAdvancedPublisherViaJNI external fun declarations matching Rust session.rs exports
- Remove all facade-typed wrapper methods (declarePublisher, declareSubscriberWith*, etc.) - these are now in zenoh-java Session.kt
- No facade imports at all
