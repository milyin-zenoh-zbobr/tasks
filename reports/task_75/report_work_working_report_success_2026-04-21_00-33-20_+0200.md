## Final Fix: Java ZBytes Call Sites

### Problem
After `ZSerializer.serialize()` and `ZDeserializer.deserialize()` were annotated with `@Throws(ZError::class)` in the zenoh-java public API layer, the Java call sites in `ZBytesTests.java` and `ZBytesExamples.java` were not updated. This caused a Java checked-exception contract violation — the methods would fail to compile without declaring or catching `ZError`.

### Fix
- `zenoh-java/src/jvmTest/java/io/zenoh/ZBytesTests.java`: Added `import io.zenoh.exceptions.ZError` and `throws ZError` to all 10 test methods.
- `examples/src/main/java/io/zenoh/ZBytesExamples.java`: Added `import io.zenoh.exceptions.ZError` and `throws ZError` to `main(String[] args)`.

### Verification
- `./gradlew :zenoh-java:jvmTest` — BUILD SUCCESSFUL, 97 tests passed
- `./gradlew :examples:compileJava` — BUILD SUCCESSFUL