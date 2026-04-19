These classes only call .close() on their JNI objects - just update imports:
- Subscriber.kt → JNISubscriber.close() - update import to runtime's
- Queryable.kt → JNIQueryable.close() - update import to runtime's  
- LivelinessToken.kt → JNILivelinessToken.close() - update import to runtime's
- MatchingListener.kt → JNIMatchingListener.close() - update import to runtime's
- SampleMissListener.kt → JNISampleMissListener.close() - update import to runtime's