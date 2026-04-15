## Summary

Removed the duplicate Android JNI packaging from `zenoh-java/build.gradle.kts`:

1. Removed `import com.nishtahir.CargoExtension`
2. Removed `apply(plugin = "org.mozilla.rust-android-gradle.rust-android")` from the `androidEnabled` block
3. Removed the `configureCargo()` call from the `androidEnabled` block  
4. Removed the `tasks.whenObjectAdded` hook that wired `mergeDebugJniLibFolders`/`mergeReleaseJniLibFolders` to `cargoBuild`
5. Removed the `fun Project.configureCargo()` function definition

`zenoh-java` still applies `com.android.library` plugin and calls `configureAndroid()` so it compiles as an Android library for its Kotlin sources, but no longer packages JNI native libraries itself. The `zenoh-jni-runtime` module is now the single owner of Android Rust/JNI compilation and packaging.

This completes the thin-wrapper split: `zenoh-java` is now a pure facade on both JVM and Android platforms, delegating JNI ownership entirely to `zenoh-jni-runtime`.