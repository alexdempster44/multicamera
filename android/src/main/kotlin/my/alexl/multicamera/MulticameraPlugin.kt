package my.alexl.multicamera

import android.app.Activity
import android.content.Context
import android.view.OrientationEventListener
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.view.TextureRegistry

class MulticameraPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    lateinit var channel: MethodChannel
        private set
    lateinit var textureRegistry: TextureRegistry
        private set
    lateinit var context: Context
        private set
    var activity: Activity? = null
        private set
    var deviceOrientation = Surface.ROTATION_0
        private set

    private val registry = Registry(this)
    private var orientationEventListener: OrientationEventListener? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "multicamera")
        channel.setMethodCallHandler(this)

        textureRegistry = flutterPluginBinding.textureRegistry
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "registerCamera" ->
                result.success(
                    registry.registerCamera(
                        Camera.Direction.entries[call.argument<Int>("direction")!!],
                        call.argument<Boolean>("paused")!!,
                        call.argument<Boolean>("recognizeText")!!,
                        call.argument<Boolean>("scanBarcodes")!!,
                        call.argument<Boolean>("detectFaces")!!
                    )
                )

            "updateCamera" -> {
                registry.updateCamera(
                    call.argument<Long>("id")!!,
                    Camera.Direction.entries[call.argument<Int>("direction")!!],
                    call.argument<Boolean>("paused")!!,
                    call.argument<Boolean>("recognizeText")!!,
                    call.argument<Boolean>("scanBarcodes")!!,
                    call.argument<Boolean>("detectFaces")!!
                )
                result.success(null)
            }

            "captureImage" -> {
                registry.captureImage(call.argument<Long>("id")!!) {
                    result.success(it)
                }
            }

            "unregisterCamera" -> {
                registry.unregisterCamera(call.argument<Long>("id")!!)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        startOrientationListener()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        stopOrientationListener()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        startOrientationListener()
    }

    override fun onDetachedFromActivity() {
        stopOrientationListener()
        activity = null
    }

    private fun startOrientationListener() {
        val activity = activity ?: return

        orientationEventListener = object : OrientationEventListener(activity) {
            override fun onOrientationChanged(orientation: Int) {
                if (orientation == ORIENTATION_UNKNOWN) return

                val rotation = arrayOf(
                    Surface.ROTATION_0,
                    Surface.ROTATION_270,
                    Surface.ROTATION_180,
                    Surface.ROTATION_90
                )[((orientation + 45) % 360) / 90]

                if (deviceOrientation != rotation) {
                    deviceOrientation = rotation
                    registry.onOrientationChanged()
                }
            }
        }

        if (orientationEventListener?.canDetectOrientation() == true) {
            orientationEventListener?.enable()
        }
    }

    private fun stopOrientationListener() {
        orientationEventListener?.disable()
        orientationEventListener = null
    }
}
