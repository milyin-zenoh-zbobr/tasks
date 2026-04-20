Modify zenoh-jni/src/utils.rs load_on_close function:
Replace the throw_exception!(env, zerror!(...)) call in the onClose callback error path with:
tracing::error!("Error while running 'onClose' callback: {}", err);
Also remove `throw_exception` from the use statement in utils.rs if it's only used there.