package my.alexl.multicamera

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.Matrix
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import java.io.Closeable
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.properties.Delegates

class PreviewFanOut(val direction: Camera.Direction) : Closeable {
    private val thread = HandlerThread("my.alexl.multicamera.preview").apply { start() }
    private val handler = Handler(thread.looper)
    private lateinit var egl: EGL

    var quarterTurns: Int = 0

    var surfaces = listOf<Surface>()
        set(value) {
            field = value
            handler.post { updateTargets() }
        }

    private var surfaceTexture: SurfaceTexture? = null
    private var surface: Surface? = null
    private val targets = mutableMapOf<Surface, EGLSurface>()
    private val textureMatrix = FloatArray(16)

    init {
        handler.post { egl = EGL() }
    }

    fun ensureSurface(size: Size): Surface {
        val surfaceTexture = surfaceTexture ?: run {
            val surfaceTexture = SurfaceTexture(this.egl.texture)
            surfaceTexture.setOnFrameAvailableListener {
                this.handler.post { this.drawFrame() }
            }

            this.surfaceTexture = surfaceTexture
            surfaceTexture
        }
        surfaceTexture.setDefaultBufferSize(size.width, size.height)

        return surface ?: run {
            val surface = Surface(surfaceTexture)

            this.surface = surface
            surface
        }
    }

    fun refreshSurfaces(surfaces: List<Surface>) {
        handler.post {
            for (surface in targets.values) {
                egl.destroySurface(surface)
            }
            targets.clear()

            for (surface in surfaces) {
                targets[surface] = egl.createSurface(surface)
            }
        }
    }

    private fun updateTargets() {
        val added = surfaces - targets.keys
        val removed = targets.keys - surfaces.toSet()

        for (surface in added) {
            targets[surface] = egl.createSurface(surface)
        }

        for (surface in removed) {
            targets.remove(surface)?.also { egl.destroySurface(it) }
        }
    }

    private fun drawFrame() {
        val surfaceTexture = surfaceTexture ?: return

        egl.bindSurface(EGL14.EGL_NO_SURFACE)
        surfaceTexture.updateTexImage()
        surfaceTexture.getTransformMatrix(textureMatrix)

        val quarterTurns = when (direction) {
            Camera.Direction.Front -> -quarterTurns + 1
            Camera.Direction.Back -> quarterTurns + 1
        }
        Matrix.translateM(textureMatrix, 0, 0.5F, 0.5F, 0F)
        Matrix.rotateM(textureMatrix, 0, quarterTurns * 90.0F, 0F, 0F, 1F)
        if (direction == Camera.Direction.Back) Matrix.scaleM(textureMatrix, 0, -1.0F, 1.0F, 0.0F)
        Matrix.translateM(textureMatrix, 0, -0.5F, -0.5F, 0F)

        for (surface in targets.values) {
            egl.drawSurface(surface, textureMatrix)
        }
    }

    override fun close() {
        handler.post {
            surface?.release()
            surfaceTexture?.release()

            for (surface in targets.values) {
                egl.destroySurface(surface)
            }
            targets.clear()

            egl.close()
        }
        thread.quitSafely()
        thread.join()
    }
}

class EGL : Closeable {
    private lateinit var display: EGLDisplay
    private lateinit var config: EGLConfig
    private lateinit var context: EGLContext

    var texture by Delegates.notNull<Int>()
        private set

    private var program: Program? = null

    init {
        createDisplay()
        createConfig()
        createContext()
        bindSurface(EGL14.EGL_NO_SURFACE)
        createTexture()
    }

    private fun createDisplay() {
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        val version = IntArray(2)

        EGL14.eglInitialize(display, version, 0, version, 1)
    }

    private fun createConfig() {
        val attributes = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
            EGLExt.EGL_RECORDABLE_ANDROID, 1,
            EGL14.EGL_NONE
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)

        EGL14.eglChooseConfig(display, attributes, 0, configs, 0, configs.size, count, 0)
        config = configs[0]!!
    }

    private fun createContext() {
        val attributes = intArrayOf(
            EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL14.EGL_NONE
        )

        context = EGL14.eglCreateContext(display, config, EGL14.EGL_NO_CONTEXT, attributes, 0)
    }

    private fun createTexture() {
        val id = IntArray(1)
        GLES20.glGenTextures(1, id, 0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, id[0])

        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MIN_FILTER,
            GLES20.GL_LINEAR
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MAG_FILTER,
            GLES20.GL_LINEAR
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_S,
            GLES20.GL_CLAMP_TO_EDGE
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_T,
            GLES20.GL_CLAMP_TO_EDGE
        )

        texture = id[0]
    }

    fun createSurface(surface: Surface): EGLSurface {
        val attributes = intArrayOf(EGL14.EGL_NONE)
        val eglSurface = EGL14.eglCreateWindowSurface(display, config, surface, attributes, 0)
        return eglSurface
    }

    fun bindSurface(surface: EGLSurface) {
        EGL14.eglMakeCurrent(display, surface, surface, context)
    }

    fun drawSurface(surface: EGLSurface, textureMatrix: FloatArray) {
        bindSurface(surface)

        val width = IntArray(1)
        val height = IntArray(1)
        EGL14.eglQuerySurface(display, surface, EGL14.EGL_WIDTH, width, 0)
        EGL14.eglQuerySurface(display, surface, EGL14.EGL_HEIGHT, height, 0)
        GLES20.glViewport(0, 0, width[0], height[0])

        GLES20.glClearColor(1.0F, 0.0F, 1.0F, 1.0F)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        val program = program ?: run {
            val program = Program()

            this.program = program
            program
        }
        program.draw(texture, textureMatrix)

        EGL14.eglSwapBuffers(display, surface)
    }

    fun destroySurface(surface: EGLSurface) {
        EGL14.eglDestroySurface(display, surface)
    }

    override fun close() {
        EGL14.eglMakeCurrent(
            display,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_CONTEXT
        )

        program?.close()
        program = null

        EGL14.eglDestroyContext(display, context)
        EGL14.eglTerminate(display)
    }
}

private class Program : Closeable {
    private var program by Delegates.notNull<Int>()
    private var aPositionLocation by Delegates.notNull<Int>()
    private var aTextureLocation by Delegates.notNull<Int>()
    private var uTextureLocation by Delegates.notNull<Int>()
    private var uTextureMatrixLocation by Delegates.notNull<Int>()

    private val vb =
        ByteBuffer.allocateDirect(64).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
            put(
                floatArrayOf(
                    -1f, -1f, 0f, 1f,
                    1f, -1f, 1f, 1f,
                    -1f, 1f, 0f, 0f,
                    1f, 1f, 1f, 0f,
                )
            ).position(0)
        }

    init {
        val vertexShader = compileShader(GLES20.GL_VERTEX_SHADER, vertexShaderSource)
        val fragmentShader = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentShaderSource)

        program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)

        GLES20.glDeleteShader(vertexShader)
        GLES20.glDeleteShader(fragmentShader)

        aPositionLocation = GLES20.glGetAttribLocation(program, "aPosition")
        aTextureLocation = GLES20.glGetAttribLocation(program, "aTexture")
        uTextureLocation = GLES20.glGetUniformLocation(program, "uTexture")
        uTextureMatrixLocation = GLES20.glGetUniformLocation(program, "uTextureMatrix")
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)

        return shader
    }

    companion object {
        val vertexShaderSource = """
            attribute vec2 aPosition;
            attribute vec2 aTexture;

            uniform mat4 uTextureMatrix;
            varying vec2 vTexture;

            void main(){
                gl_Position = vec4(aPosition, 0.0, 1.0);
                vec4 texture = uTextureMatrix * vec4(aTexture, 0.0, 1.0);
                vTexture = texture.xy;
            }
        """.trimIndent()

        val fragmentShaderSource = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;

            varying vec2 vTexture;

            uniform samplerExternalOES uTexture;

            void main(){
                gl_FragColor = texture2D(uTexture, vTexture);
            }
        """.trimIndent()
    }

    fun draw(texture: Int, textureMatrix: FloatArray) {
        GLES20.glUseProgram(program)

        vb.position(0)
        GLES20.glVertexAttribPointer(aPositionLocation, 2, GLES20.GL_FLOAT, false, 16, vb)
        GLES20.glEnableVertexAttribArray(aPositionLocation)
        vb.position(2)
        GLES20.glVertexAttribPointer(aTextureLocation, 2, GLES20.GL_FLOAT, false, 16, vb)
        GLES20.glEnableVertexAttribArray(aTextureLocation)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
        GLES20.glUniform1i(uTextureLocation, 0)

        GLES20.glUniformMatrix4fv(uTextureMatrixLocation, 1, false, textureMatrix, 0)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    override fun close() {
        GLES20.glDeleteProgram(program)
    }
}
