Publisher.kt:
- put: extract bytes from payload/encoding → jniPublisher?.put(payload.into().bytes, enc.id, enc.schema, attachment?.into()?.bytes)
- delete: jniPublisher?.delete(attachment?.into()?.bytes)

AdvancedPublisher.kt:
- put: extract bytes same as Publisher
- declareMatchingListener: create JNIMatchingListenerCallback lambda, then call with jniCallback
- getMatchingStatus: runCatching { jniPublisher.getMatchingStatus() } (returns Boolean, not Result<Boolean>)

AdvancedSubscriber.kt (major adaptation):
For declareDetectPublishersSubscriber variants:
1. Construct JNISubscriberCallback lambda building Sample from raw params
2. Wrap onClose in JNIOnCloseCallback lambda
3. Call jniSubscriber.declareDetectPublishersSubscriber(history, jniCallback, jniOnClose) → JNISubscriber
4. Wrap in Subscriber(keyExpr, receiver, jniSubscriber)
5. Use runCatching {}

For declareSampleMissListener variants:
1. Construct JNISampleMissListenerCallback lambda building SampleMiss from raw params
2. Wrap onClose in JNIOnCloseCallback lambda
3. Call jniSubscriber.declareSampleMissListener(jniCallback, jniOnClose) → JNISampleMissListener
4. Wrap in SampleMissListener(jniSampleMissListener)
5. Use runCatching {}