package my.alexl.multicamera

import android.media.Image
import android.os.Handler
import android.os.Looper

class Registry(val plugin: MulticameraPlugin) {
    val cameras = HashMap<Long, Camera>()
    val cameraHandles = HashMap<Camera.Direction, CameraHandle>()

    fun registerCamera(
        direction: Camera.Direction,
        paused: Boolean,
        recognizeText: Boolean,
        scanBarcodes: Boolean,
        detectFaces: Boolean
    ): Long {
        val camera = Camera(
            plugin,
            direction,
            paused,
            recognizeText,
            scanBarcodes,
            detectFaces
        )
        cameras[camera.id] = camera
        reconcile()

        return camera.id
    }

    fun updateCamera(
        id: Long,
        direction: Camera.Direction,
        paused: Boolean,
        recognizeText: Boolean,
        scanBarcodes: Boolean,
        detectFaces: Boolean
    ) {
        cameras[id]?.let {
            it.direction = direction
            it.paused = paused
            it.recognizeText = recognizeText
            it.scanBarcodes = scanBarcodes
            it.detectFaces = detectFaces
            reconcile()
        }
    }

    fun unregisterCamera(id: Long) {
        cameras.remove(id)?.close()
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
        for (direction in Camera.Direction.entries) {
            val cameras = cameras.values.filter { it.direction == direction }
            val handleRequired = !cameras.isEmpty()

            if (handleRequired) {
                val handle = cameraHandles.computeIfAbsent(direction) {
                    CameraHandle(
                        plugin,
                        direction,
                        onStateChanged = { updateFlutterCameras(direction) },
                        onRecognitionImage = { image, onComplete ->
                            onRecognitionImage(
                                image,
                                direction,
                                onComplete
                            )
                        }
                    )
                }
                handle.surfaceProducers = cameras.filter { !it.paused }.map { it.surfaceProducer }
            } else {
                cameraHandles.remove(direction)?.close()
            }
            updateFlutterCameras(direction)
        }
    }

    private fun updateFlutterCameras(direction: Camera.Direction) {
        val handle = cameraHandles[direction] ?: return
        val cameras = cameras.values.filter { it.direction == direction && !it.paused }

        var width = handle.size.width
        var height = handle.size.height
        if (handle.quarterTurns % 2 == 1) {
            width = height.also { height = width }
        }

        for (camera in cameras) {
            Handler(Looper.getMainLooper()).post {
                plugin.channel.invokeMethod(
                    "updateCamera",
                    mapOf(
                        "id" to camera.id,
                        "width" to width,
                        "height" to height,
                    )
                )
            }
        }
    }

    private fun onRecognitionImage(
        image: Image,
        direction: Camera.Direction,
        onComplete: () -> Unit
    ) {
        val cameras = cameras.values.filter { it.direction == direction && !it.paused }

        val recognizeText = cameras.any { it.recognizeText }
        val scanBarcodes = cameras.any { it.scanBarcodes }
        val detectFaces = cameras.any { it.detectFaces }

        try {
            ImageRecognition.recognizeImage(
                image,
                recognizeText,
                scanBarcodes,
                detectFaces
            ) { results ->
                val cameras = this.cameras.values.filter { it.direction == direction && !it.paused }
                for (camera in cameras) {
                    Handler(Looper.getMainLooper()).post {
                        plugin.channel.invokeMethod(
                            "recognitionResults",
                            mapOf(
                                "id" to camera.id,
                                "text" to results.text,
                                "barcodes" to results.barcodes,
                                "face" to results.face
                            )
                        )
                    }
                }

                onComplete()
            }
        } catch (_: IllegalStateException) {
            // Ignore
        }
    }
}
