package my.alexl.multicamera

import android.os.Handler
import android.os.Looper

class Registry(val plugin: MulticameraPlugin) {
    val cameras = HashMap<Long, Camera>()
    val cameraHandles = HashMap<CameraDirection, CameraHandle>()

    fun registerCamera(direction: CameraDirection, paused: Boolean): Long {
        val camera = Camera(plugin, direction, paused)
        cameras[camera.id] = camera
        reconcile()

        return camera.id
    }

    fun updateCamera(id: Long, direction: CameraDirection, paused: Boolean) {
        cameras[id]?.let {
            it.direction = direction
            it.paused = paused
            reconcile()
        }
    }

    fun unregisterCamera(id: Long) {
        cameras.remove(id)
        reconcile()
    }

    fun captureImage(id: Long, callback: (ByteArray?) -> Unit) {
        val camera = cameras[id]
        if (camera == null) {
            callback(null)
            return
        }

        val handle = cameraHandles[camera.direction]
        if (handle == null) {
            callback(null)
            return
        }

        handle.captureImage(callback)
    }

    fun onOrientationChanged() {
        for (handle in cameraHandles.values) {
            handle.updateOrientation()
        }
    }

    private fun reconcile() {
        for (direction in CameraDirection.entries) {
            val cameras = cameras.values.filter { it.direction == direction }
            val handleRequired = !cameras.isEmpty()

            updateFlutterCameras(direction)
            if (handleRequired) {
                val handle = cameraHandles.computeIfAbsent(direction) {
                    CameraHandle(
                        plugin,
                        direction
                    ) { updateFlutterCameras(direction) }
                }
                handle.surfaceProducers = cameras.filter { !it.paused }.map { it.surfaceProducer }
            } else {
                cameraHandles.remove(direction)?.close()
            }
        }
    }

    private fun updateFlutterCameras(direction: CameraDirection) {
        val handle = cameraHandles[direction] ?: return
        val cameras = cameras.values.filter { it.direction == direction }

        for (camera in cameras) {
            Handler(Looper.getMainLooper()).post {
                plugin.channel.invokeMethod(
                    "updateCamera",
                    mapOf(
                        "id" to camera.id,
                        "width" to handle.size.width,
                        "height" to handle.size.height,
                        "quarterTurns" to handle.quarterTurns
                    )
                )
            }
        }
    }
}
