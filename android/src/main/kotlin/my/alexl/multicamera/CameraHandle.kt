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
                size?.apply { it.setSize(width, height) }
                it.surface
            }
        }
    var size: Size? = null
        private set
    var quarterTurns = 0
        private set

    private var previewFanOut = PreviewFanOut(direction)
    private lateinit var thread: HandlerThread
    private lateinit var handler: Handler
    private var device: CameraDevice? = null
    private var characteristics: CameraCharacteristics? = null
    private var pendingCaptureCallbacks = mutableListOf<(ByteArray?) -> Unit>()
    private var imageReader: ImageReader? = null
    private var recognitionImageReader: ImageReader? = null
    private var lastRecognitionTime: Long = 0
    private var recognitionBusy = false

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
        pendingCaptureCallbacks.add(callback)
    }

    private fun createSession() {
        val device = device ?: return
        val size = size ?: return

        val previewSurface = previewFanOut.ensureSurface(size)

        val imageReader = ImageReader.newInstance(
            size.width,
            size.height,
            ImageFormat.YUV_420_888,
            2
        )
        imageReader.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage()
            if (image == null) return@setOnImageAvailableListener

            val callbacks = pendingCaptureCallbacks.toList()
            pendingCaptureCallbacks.clear()
            if (callbacks.isNotEmpty()) {
                val data = image.toJpeg(quarterTurns)
                for (callback in callbacks) callback(data)
            }

            image.close()
        }, handler)
        this.imageReader = imageReader

        val recognitionImageReader = ImageReader.newInstance(
            (size.width * 0.2).toInt(),
            (size.height * 0.2).toInt(),
            ImageFormat.YUV_420_888,
            2
        )
        recognitionImageReader.setOnImageAvailableListener({ reader ->
            if (recognitionBusy) return@setOnImageAvailableListener
            val now = System.currentTimeMillis()
            if (now - lastRecognitionTime < 200) return@setOnImageAvailableListener

            val image = reader.acquireLatestImage()
            if (image == null) return@setOnImageAvailableListener

            lastRecognitionTime = now
            recognitionBusy = true
            onRecognitionImage(image) { recognitionBusy = false }
        }, handler)
        this.recognitionImageReader = recognitionImageReader

        val sessionConfiguration = SessionConfiguration(
            SessionConfiguration.SESSION_REGULAR,
            listOf(
                OutputConfiguration(previewSurface),
                OutputConfiguration(imageReader.surface),
                OutputConfiguration(recognitionImageReader.surface)
            ),
            { handler.post(it) },
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(captureSession: CameraCaptureSession) {
                    try {
                        val request = device
                            .createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                            .apply {
                                addTarget(previewSurface)
                                addTarget(imageReader.surface)
                                addTarget(recognitionImageReader.surface)
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

    private fun openThread() {
        thread = HandlerThread("my.alexl.multicamera.${direction.name}").apply { start() }
        handler = Handler(thread.looper)
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

    private fun closeDevice() {
        imageReader?.close()
        imageReader = null
        recognitionImageReader?.close()
        recognitionImageReader = null
        device?.close()
        device = null
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

    override fun close() {
        handler.post { closeDevice() }
        thread.quitSafely()
        thread.join()
        previewFanOut.close()
    }
}
