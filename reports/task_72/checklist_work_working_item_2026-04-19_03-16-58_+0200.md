Query.kt:
- replySuccess/replyDelete/replyError: extract primitives from Sample/IntoZBytes and call runtime's jniQuery methods with primitive args

Querier.kt:
- performGet: set up JNIGetCallback and JNIOnCloseCallback lambdas inline, then call runtime jniQuerier.get() with primitives

Zenoh.kt (Scout):
- Create JNIScoutCallback lambda constructing Hello domain objects from raw params
- compute whatAmI as Int (OR of WhatAmI.value)
- call JNIScout.scout(whatAmI, jniCallback, onClose, config?.jniConfig)