package my.alexl.multicamera

import io.flutter.view.TextureRegistry
import java.io.Closeable

class Camera(
    plugin: MulticameraPlugin,
    var direction: CameraDirection,
    var paused: Boolean
) : Closeable {
    val surfaceProducer: TextureRegistry.SurfaceProducer =
        plugin.textureRegistry.createSurfaceProducer()

    val id: Long
        get() = surfaceProducer.id()

    override fun close() {
        surfaceProducer.release()
    }
}

enum class CameraDirection {
    Front,
    Back
}
