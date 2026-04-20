publisher.rs:
- putViaJNI: Unit -> jint, -1 on error
- deleteViaJNI: Unit -> jint, -1 on error

query.rs:
- replySuccessViaJNI: Unit -> jint, -1 on error
- replyErrorViaJNI: Unit -> jint, -1 on error
- replyDeleteViaJNI: Unit -> jint, -1 on error

querier.rs:
- getViaJNI: Unit -> jint, -1 on error

scouting.rs:
- scoutViaJNI: return null on error

zbytes.rs:
- serializeViaJNI: jobject -> return JObject::default().as_raw() (null) on error
- deserializeViaJNI: same

zbytes_kotlin.rs:
- serializeViaJNI: same
- deserializeViaJNI: same

ext/advanced_publisher.rs:
- putViaJNI: Unit -> jint, -1 on error
- deleteViaJNI: Unit -> jint, -1 on error
- declareMatchingListenerViaJNI: return null on error
- declareBackgroundMatchingListenerViaJNI: Unit -> jint, -1 on error
- getMatchingStatusViaJNI: jboolean -> jint, -1 on error

ext/advanced_subscriber.rs:
- declareDetectPublishersSubscriberViaJNI: return null on error
- declareSampleMissListenerViaJNI: return null on error
- declareBackgroundDetectPublishersSubscriberViaJNI: Unit -> jint, -1 on error
- declareBackgroundSampleMissListenerViaJNI: Unit -> jint, -1 on error