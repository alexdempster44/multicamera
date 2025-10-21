package my.alexl.multicamera

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureFailure
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import androidx.annotation.RequiresPermission
import io.flutter.view.TextureRegistry
import java.io.Closeable

@SuppressLint("MissingPermission")
class CameraHandle(
    val plugin: MulticameraPlugin,
    val direction: CameraDirection,
    val onStateChanged: () -> Unit,
) : Closeable, CameraDevice.StateCallback() {
    var surfaceProducers = listOf<TextureRegistry.SurfaceProducer>()
        set(value) {
            field = value
            handler.post { createSession() }
        }
    var size = Size(1024, 1024)
        private set
    var quarterTurns = 0
        private set

    private lateinit var thread: HandlerThread
    private lateinit var handler: Handler
    private var device: CameraDevice? = null
    private var characteristics: CameraCharacteristics? = null
    private var session: CameraCaptureSession? = null
    private var captureInProgress: Boolean = false
    private var pendingCaptureCallbacks = mutableListOf<(ByteArray?) -> Unit>()

    private val cameraManager: CameraManager by lazy {
        plugin.context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    }

    init {
        openThread()
        handler.post @RequiresPermission(Manifest.permission.CAMERA) { openDevice() }
    }

    fun updateOrientation() {
        handler.post {
            calculateQuarterTurns()
            onStateChanged()
        }
    }

    fun captureImage(callback: (ByteArray?) -> Unit) {
        handler.post {
            pendingCaptureCallbacks.add(callback)
            createSession()
        }
    }

    private fun createSession() {
        if (pendingCaptureCallbacks.isEmpty()) {
            createPreviewSession()
        } else {
            if (!captureInProgress) createCaptureSession()
        }
    }

    private fun createPreviewSession() {
        val device = device ?: return

        var surfaces = surfaceProducers.map {
            it.setSize(size.width, size.height)
            it.surface
        }

        if (surfaces.isEmpty()) {
            try {
                session?.apply { stopRepeating() }
            } catch (_: IllegalStateException) {
                // Session closed
            }

            return
        }

        val outputConfiguration = OutputConfiguration(surfaces.first())
        outputConfiguration.enableSurfaceSharing()

        surfaces = surfaces.take(outputConfiguration.maxSharedSurfaceCount)
        for (additionalSurface in surfaces.drop(1)) {
            outputConfiguration.addSurface(additionalSurface)
        }

        val sessionConfiguration = SessionConfiguration(
            SessionConfiguration.SESSION_REGULAR,
            listOf(outputConfiguration),
            { handler.post(it) },
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(captureSession: CameraCaptureSession) {
                    session = captureSession

                    try {
                        val request = device
                            .createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                            .apply {
                                surfaces.forEach { addTarget(it) }
                            }

                        captureSession.setRepeatingRequest(request.build(), null, null)
                    } catch (_: IllegalStateException) {
                        // Session closed
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {}
            }
        )
        device.createCaptureSession(sessionConfiguration)
    }

    private fun createCaptureSession() {
        val device = device ?: return

        if (captureInProgress) return
        captureInProgress = true

        val imageReader = ImageReader.newInstance(
            size.width,
            size.height,
            ImageFormat.JPEG,
            1
        )

        val surface = imageReader.surface
        val outputConfiguration = OutputConfiguration(surface)

        val sessionConfiguration = SessionConfiguration(
            SessionConfiguration.SESSION_REGULAR,
            listOf(outputConfiguration),
            { handler.post(it) },
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(captureSession: CameraCaptureSession) {
                    session = captureSession

                    imageReader.setOnImageAvailableListener({
                        val image = it.acquireLatestImage()
                        if (image == null) {
                            completeCapture(null)
                        } else {
                            try {
                                val buffer = image.planes[0].buffer
                                val bytes = ByteArray(buffer.remaining())
                                buffer.get(bytes)

                                completeCapture(bytes)
                            } finally {
                                image.close()
                            }
                        }

                        captureSession.close()
                        imageReader.close()

                        createSession()
                    }, handler)

                    val request = device
                        .createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
                        .apply {
                            addTarget(imageReader.surface)
                            set(CaptureRequest.JPEG_ORIENTATION, quarterTurns * 90)
                        }

                    captureSession.capture(
                        request.build(),
                        object : CameraCaptureSession.CaptureCallback() {
                            override fun onCaptureFailed(
                                session: CameraCaptureSession,
                                request: CaptureRequest,
                                failure: CaptureFailure
                            ) {
                                completeCapture(null)
                                captureSession.close()
                                imageReader.close()

                                createSession()
                            }
                        },
                        handler
                    )
                }

                override fun onConfigureFailed(captureSession: CameraCaptureSession) {
                    completeCapture(null)
                    imageReader.close()

                    createSession()
                }
            }
        )
        device.createCaptureSession(sessionConfiguration)
    }

    private fun openThread() {
        thread = HandlerThread("my.alexl.multicamera.${direction.name}").apply { start() }
        handler = Handler(thread.looper)
    }

    @RequiresPermission(Manifest.permission.CAMERA)
    private fun openDevice() {
        val lensFacing = when (direction) {
            CameraDirection.Front -> CameraCharacteristics.LENS_FACING_FRONT
            CameraDirection.Back -> CameraCharacteristics.LENS_FACING_BACK
        }

        val cameraIds = cameraManager.cameraIdList
        val cameraId = cameraIds.firstOrNull {
            val chars = cameraManager.getCameraCharacteristics(it)
            chars.get(CameraCharacteristics.LENS_FACING) == lensFacing
        } ?: cameraIds.first()

        characteristics = cameraManager.getCameraCharacteristics(cameraId)
        calculateSize()
        calculateQuarterTurns()
        onStateChanged()

        cameraManager.openCamera(cameraId, this, null)
    }

    private fun calculateSize() {
        val characteristics = characteristics ?: return
        val streamConfigurationMap =
            characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return
        val sizes = streamConfigurationMap.getOutputSizes(SurfaceTexture::class.java)

        size = sizes.maxBy { it.width * it.height }
    }

    private fun calculateQuarterTurns() {
        val characteristics = characteristics ?: return
        val sensorOrientation =
            characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: return

        val degrees = when (plugin.deviceOrientation) {
            Surface.ROTATION_0 -> 0
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> return
        }

        val rotation = when (direction) {
            CameraDirection.Front -> (sensorOrientation + degrees) % 360
            CameraDirection.Back -> (sensorOrientation - degrees + 360) % 360
        }

        quarterTurns = rotation / 90
    }

    private fun completeCapture(image: ByteArray?) {
        val callbacks = pendingCaptureCallbacks.toList()
        pendingCaptureCallbacks.clear()
        captureInProgress = false

        for (callback in callbacks) {
            callback(image)
        }
    }

    private fun closeDevice() {
        device?.close()
        device = null
    }

    private fun closeThread() {
        thread.quitSafely()
        thread.join()
    }

    override fun onOpened(camera: CameraDevice) {
        device = camera
        createSession()
    }

    override fun onDisconnected(camera: CameraDevice) {
        device = camera
        closeDevice()
    }

    override fun onError(camera: CameraDevice, error: Int) {
        device = camera
        closeDevice()
    }

    override fun onClosed(camera: CameraDevice) {
        closeThread()
    }

    override fun close() {
        handler.post { closeDevice() }
    }
}
