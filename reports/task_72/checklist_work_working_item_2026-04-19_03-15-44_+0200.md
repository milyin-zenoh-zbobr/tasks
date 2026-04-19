1. Create zenoh-kotlin/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ directory
2. Move ZSerialize.kt and ZDeserialize.kt from commonMain to jvmAndAndroidMain
3. Update imports to use JNIZBytesKotlin from runtime instead of local JNIZBytes