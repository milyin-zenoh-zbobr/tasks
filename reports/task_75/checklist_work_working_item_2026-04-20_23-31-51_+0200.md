Create `zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` with same package and class:
```kotlin
package io.zenoh.exceptions
class ZError(override val message: String? = null) : Exception()
```