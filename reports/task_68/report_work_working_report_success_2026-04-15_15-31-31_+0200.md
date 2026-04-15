## Summary

The only remaining issue was that `zenoh-jni-runtime/src/androidMain/AndroidManifest.xml` was missing, despite `build.gradle.kts` configuring the Android source set to reference it.

### Fix Applied
Created `zenoh-jni-runtime/src/androidMain/AndroidManifest.xml` with the same minimal manifest content used by `zenoh-java/src/androidMain/AndroidManifest.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"/>
```

This ensures the `zenoh-jni-runtime` module is fully wired for Android when Gradle is invoked with `-Pandroid=true`, matching the established pattern from the existing `zenoh-java` module and unblocking Android artifact publication.