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
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.Image
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
    val direction: Camera.Direction,
    val onStateChanged: () -> Unit,
    val onRecognitionImage: (Image, () -> Unit) -> Unit,
) : Closeable, CameraDevice.StateCallback() {
    var surfaceProducers = listOf<TextureRegistry.SurfaceProducer>()
        set(value) {
            field = value
            previewFanOut.surfaces = value.map {
                it.setSize(size.width, size.height)
                it.surface
            }

            setupSession()
        }
    var size = Size(1, 1)
        private set
    var quarterTurns = 0
        private set

    private var previewFanOut = PreviewFanOut(direction)
    private val thread = HandlerThread("my.alexl.multicamera.${direction.name}").apply { start() }
    private val handler = Handler(thread.looper)
    private var device: CameraDevice? = null
    private var characteristics: CameraCharacteristics? = null
    private var pendingCaptureCallbacks = mutableListOf<(ByteArray?) -> Unit>()
    private var captureImageReader: ImageReader? = null
    private var recognitionImageReader: ImageReader? = null
    private var session: CameraCaptureSession? = null
    private var recognitionBusy = false

    private val cameraManager: CameraManager by lazy {
        plugin.context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    }

    init {
        handler.post @RequiresPermission(Manifest.permission.CAMERA) { openDevice() }
    }

    fun updateOrientation() {
        handler.post {
            calculateQuarterTurns()
            onStateChanged()
        }
    }

    fun captureImage(callback: (ByteArray?) -> Unit) {
        pendingCaptureCallbacks.add(callback)
        handler.post { setupSessionRequest(capture = true) }
    }

    private fun setupSession() {
        val sessionRequired = surfaceProducers.isNotEmpty() || pendingCaptureCallbacks.isNotEmpty()
        val hasSession = session != null
        if (sessionRequired == hasSession) return

        if (sessionRequired) {
            createSession()
        } else {
            closeSession()
        }
    }

    private fun createSession() {
        if (session != null) return
        val device = device ?: return

        val previewSurface = previewFanOut.ensureSurface(size)

        val captureImageReader = ImageReader.newInstance(
            size.width,
            size.height,
            ImageFormat.JPEG,
            2
        )
        captureImageReader.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener

            val callbacks = pendingCaptureCallbacks.toList()
            pendingCaptureCallbacks.clear()
            if (callbacks.isNotEmpty()) {
                val buffer = image.planes[0].buffer
                val bytes = ByteArray(buffer.remaining())
                buffer.get(bytes)

                for (callback in callbacks) callback(bytes)
            }

            image.close()
        }, handler)
        this.captureImageReader = captureImageReader

        val recognitionImageReader = ImageReader.newInstance(
            (size.width * 0.2).toInt(),
            (size.height * 0.2).toInt(),
            ImageFormat.YUV_420_888,
            2
        )
        recognitionImageReader.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener

            if (recognitionBusy) {
                image.close()
                return@setOnImageAvailableListener
            }

            recognitionBusy = true
            onRecognitionImage(image) {
                handler.postDelayed({
                    recognitionBusy = false
                }, 200)
            }
        }, handler)
        this.recognitionImageReader = recognitionImageReader

        val sessionConfiguration = SessionConfiguration(
            SessionConfiguration.SESSION_REGULAR,
            listOf(
                OutputConfiguration(previewSurface),
                OutputConfiguration(captureImageReader.surface),
                OutputConfiguration(recognitionImageReader.surface)
            ),
            { handler.post(it) },
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(captureSession: CameraCaptureSession) {
                    try {
                        session = captureSession
                        setupSessionRequest(capture = pendingCaptureCallbacks.isNotEmpty())
                    } catch (_: IllegalStateException) {
                        // Session closed
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {}
            }
        )
        device.createCaptureSession(sessionConfiguration)
    }

    @RequiresPermission(Manifest.permission.CAMERA)
    private fun openDevice() {
        val lensFacing = when (direction) {
            Camera.Direction.Front -> CameraCharacteristics.LENS_FACING_FRONT
            Camera.Direction.Back -> CameraCharacteristics.LENS_FACING_BACK
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

        val size = sizes.maxBy { it.width * it.height }
        this.size = size

        previewFanOut.refreshSurfaces(surfaceProducers.map {
            it.setSize(size.width, size.height)
            it.surface
        })
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
            Camera.Direction.Front -> (sensorOrientation + degrees) % 360
            Camera.Direction.Back -> (sensorOrientation - degrees + 360) % 360
        }

        quarterTurns = rotation / 90
        previewFanOut.quarterTurns = quarterTurns
    }

    private fun setupSessionRequest(capture: Boolean = false) {
        val device = device ?: return
        val session = session ?: return

        val previewSurface = previewFanOut.ensureSurface(size)
        val captureImageReader = captureImageReader ?: return
        val recognitionImageReader = recognitionImageReader ?: return

        val request = device
            .createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            .apply {
                addTarget(previewSurface)
                if (capture) addTarget(captureImageReader.surface)
                addTarget(recognitionImageReader.surface)
            }

        try {
            if (capture) {
                session.capture(request.build(), null, null)
            } else {
                session.setRepeatingRequest(request.build(), null, null)
            }
        } catch (_: IllegalStateException) {
            // Session closed
        }
    }

    private fun closeSession() {
        session?.apply { close() }
        session = null
        captureImageReader?.close()
        captureImageReader = null
        recognitionImageReader?.close()
        recognitionImageReader = null
    }

    private fun closeDevice() {
        closeSession()
        device?.close()
        device = null
    }

    override fun onOpened(camera: CameraDevice) {
        device = camera
        setupSession()
    }

    override fun onDisconnected(camera: CameraDevice) {
        device = camera
        closeDevice()
    }

    override fun onError(camera: CameraDevice, error: Int) {
        device = camera
        closeDevice()
    }

    override fun close() {
        handler.post { closeDevice() }
        thread.quitSafely()
        thread.join()
        previewFanOut.close()
    }
}
