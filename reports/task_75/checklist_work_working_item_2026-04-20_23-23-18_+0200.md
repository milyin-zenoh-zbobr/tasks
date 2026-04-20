For each exported function in session.rs add error_out: JObjectArray as last parameter:
- openSessionViaJNI: return 0 on error (as *const Session which is null)
- openSessionWithJsonConfigViaJNI: same
- openSessionWithYamlConfigViaJNI: same
- declarePublisherViaJNI: return null on error
- putViaJNI: Unit -> jint, -1 on error
- deleteViaJNI: Unit -> jint, -1 on error
- declareSubscriberViaJNI: return null on error
- declareQuerierViaJNI: return null on error
- declareQueryableViaJNI: return null on error
- declareKeyExprViaJNI: return null on error
- getViaJNI: Unit -> jint, -1 on error
- getPeersZidViaJNI: return JObject::default().as_raw() on error  
- getRoutersZidViaJNI: return JObject::default().as_raw() on error
- getZidViaJNI: return JByteArray::default().as_raw() (null) on error
- declareLivelinessTokenViaJNI: in liveliness.rs, return null on error
- declareLivelinessSubscriberViaJNI: in liveliness.rs, return null on error
- livelinessGetViaJNI: in liveliness.rs, Unit -> jint, -1 on error
- declareAdvancedSubscriberViaJNI: return null on error
- declareAdvancedPublisherViaJNI: return null on error

Note: undeclareKeyExprViaJNI is excluded (always succeeds)
Note: closeSessionViaJNI is excluded (always succeeds)