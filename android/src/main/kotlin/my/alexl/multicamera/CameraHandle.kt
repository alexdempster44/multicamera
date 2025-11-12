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
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import androidx.annotation.RequiresPermission
import androidx.exifinterface.media.ExifInterface
import io.flutter.view.TextureRegistry
import java.io.Closeable
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

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
    private var captureBusy = false
    private var recognitionBusy = false

    private val captureCallback = object : CameraCaptureSession.CaptureCallback() {
        override fun onCaptureCompleted(
            session: CameraCaptureSession,
            request: CaptureRequest,
            result: TotalCaptureResult
        ) {
            val exposureLevelled = listOf(
                CaptureResult.CONTROL_AE_STATE_CONVERGED,
                CaptureResult.CONTROL_AE_STATE_LOCKED
            ).contains(result.get(CaptureResult.CONTROL_AE_STATE))

            if (!captureBusy &&
                pendingCaptureCallbacks.isNotEmpty() &&
                exposureLevelled
            ) {
                captureBusy = true
                setupSessionRequest(capture = true)
            }
        }
    }

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
        handler.post { pendingCaptureCallbacks.add(callback) }
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
            val image = reader.acquireNextImage() ?: return@setOnImageAvailableListener

            val callbacks = pendingCaptureCallbacks.toList()
            pendingCaptureCallbacks.clear()
            if (callbacks.isNotEmpty()) {
                val buffer = image.planes[0].buffer
                val bytes = ByteArray(buffer.remaining())
                buffer.get(bytes)

                val bytesWithExif = addExifOrientation(bytes)
                for (callback in callbacks) callback(bytesWithExif)
            }

            image.close()
            captureBusy = false
            setupSessionRequest()
        }, handler)
        this.captureImageReader = captureImageReader

        val recognitionImageReader = ImageReader.newInstance(
            (size.width * 0.2).toInt(),
            (size.height * 0.2).toInt(),
            ImageFormat.YUV_420_888,
            2
        )
        recognitionImageReader.setOnImageAvailableListener({ reader ->
            val image = reader.acquireNextImage() ?: return@setOnImageAvailableListener

            if (recognitionBusy) {
                image.close()
                return@setOnImageAvailableListener
            }

            recognitionBusy = true
            onRecognitionImage(image) {
                handler.postDelayed({
                    image.close()
                    recognitionBusy = false
                }, 200)
            }
        }, handler)
        this.recognitionImageReader = recognitionImageReader

        @Suppress("DEPRECATION")
        device.createCaptureSession(
            listOf(
                previewSurface,
                captureImageReader.surface,
                recognitionImageReader.surface
            ),
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(captureSession: CameraCaptureSession) {
                    session = captureSession
                    setupSessionRequest()
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {}
            },
            handler
        )
    }

    @RequiresPermission(Manifest.permission.CAMERA)
    private fun openDevice() {
        try {
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
        } catch (_: Exception) {
            closeDevice()
        }
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

    private fun addExifOrientation(bytes: ByteArray): ByteArray {
        val file = File.createTempFile("capture", ".jpg", plugin.context.cacheDir)
        try {
            FileOutputStream(file).use { it.write(bytes) }

            val exif = ExifInterface(file.absolutePath)
            val exifOrientation = when (quarterTurns % 4) {
                1 -> ExifInterface.ORIENTATION_ROTATE_90
                2 -> ExifInterface.ORIENTATION_ROTATE_180
                3 -> ExifInterface.ORIENTATION_ROTATE_270
                else -> ExifInterface.ORIENTATION_NORMAL
            }
            exif.setAttribute(ExifInterface.TAG_ORIENTATION, exifOrientation.toString())
            exif.saveAttributes()

            return FileInputStream(file).use { it.readBytes() }
        } finally {
            file.delete()
        }
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
                session.capture(request.build(), captureCallback, null)
            } else {
                session.setRepeatingRequest(request.build(), captureCallback, null)
            }
        } catch (_: IllegalStateException) {
            // Session closed
        }
    }

    private fun closeSession() {
        for (callback in pendingCaptureCallbacks) callback(null)
        pendingCaptureCallbacks.clear()
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
