## Overall assessment
The implementation now satisfies the task requirements.

The branch removes zenoh-kotlin’s in-repo JNI/Rust implementation, rewires the Kotlin library to depend on `org.eclipse.zenoh:zenoh-jni-runtime`, keeps the local `zenoh-java` submodule strictly as an opt-in local-dev/test path, and updates CI/release/docs consistently with that model.

I did not find any remaining task-related correctness, architecture, or release-workflow issues in the final diff.

## Analog consistency
The migration is consistent with the chosen analog: `zenoh-java` on the `common-jni` branch.

In particular:
- Kotlin wrappers now call runtime JNI classes directly with the same primitive/JNI-level adaptation pattern used upstream.
- `Query` / `Queryable` handling now matches the analog again: the callback-provided `acceptReplies` value is preserved, and selector parameter parsing is fail-fast instead of silently degrading.
- The `ZSerialize` / `ZDeserialize` move to `jvmAndAndroidMain` aligns with the runtime layout.
- The build wiring follows the intended split: Maven dependency by default, composite-build substitution only when `-Pzenoh.useLocalJniRuntime=true` is explicitly requested.

## Task requirements review
I verified the final branch against the stated task:
- `zenoh-java` is added as a git submodule on the expected branch for local building/testing.
- Published `zenoh-kotlin` depends on `zenoh-jni-runtime` rather than building/bundling its own JNI layer.
- All Rust code owned by this repository has been removed.
- Release automation no longer tries to publish the deleted Rust crate.
- Documentation now distinguishes the default Maven path from the opt-in local submodule path.
- No user-level API break stood out in the reviewed Kotlin sources.

## Checklist status
I did not find any remaining unchecked checklist items in the provided task context. All listed phases/fixes are complete.

## Findings
No blocking findings.