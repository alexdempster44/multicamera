package my.alexl.multicamera

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

fun Image.toJpeg(quarterTurns: Int = 0): ByteArray {
    val nv21 = ByteArray(width * height + (width * height / 2))

    val yPlane = planes[0]
    copyYPlane(
        yPlane.buffer,
        width,
        height,
        yPlane.rowStride,
        yPlane.pixelStride,
        nv21
    )

    val uPlane = planes[1]
    val vPlane = planes[2]
    copyUVPlanes(
        uPlane.buffer,
        vPlane.buffer,
        width,
        height,
        uPlane.rowStride,
        vPlane.rowStride,
        uPlane.pixelStride,
        vPlane.pixelStride,
        nv21
    )

    val jpegData = ByteArrayOutputStream().use {
        val image = YuvImage(nv21, ImageFormat.NV21, width, height, null)
        image.compressToJpeg(Rect(0, 0, width, height), 80, it)
        it.toByteArray()
    }

    val orientation = when ((quarterTurns % 4 + 4) % 4) {
        1 -> ExifInterface.ORIENTATION_ROTATE_90
        2 -> ExifInterface.ORIENTATION_ROTATE_180
        3 -> ExifInterface.ORIENTATION_ROTATE_270
        else -> ExifInterface.ORIENTATION_NORMAL
    }

    val temporaryFile = java.io.File.createTempFile("capture", ".jpg")
    temporaryFile.writeBytes(jpegData)

    val exif = ExifInterface(temporaryFile.absolutePath)
    exif.setAttribute(ExifInterface.TAG_ORIENTATION, orientation.toString())
    exif.saveAttributes()

    return temporaryFile.readBytes()
}

private fun copyYPlane(
    yBuffer: ByteBuffer,
    width: Int,
    height: Int,
    rowStride: Int,
    pixelStride: Int,
    destination: ByteArray
) {
    var destinationIndex = 0
    var sourceRowStart = 0

    repeat(height) {
        var sourceIndex = sourceRowStart
        if (pixelStride == 1) {
            yBuffer.position(sourceIndex)
            yBuffer.get(destination, destinationIndex, width)
            destinationIndex += width
        } else {
            var writeIndex = destinationIndex
            repeat(width) {
                destination[writeIndex++] = yBuffer.get(sourceIndex)
                sourceIndex += pixelStride
            }
            destinationIndex += width
        }
        sourceRowStart += rowStride
    }
}

private fun copyUVPlanes(
    uBuffer: ByteBuffer,
    vBuffer: ByteBuffer,
    width: Int,
    height: Int,
    uRowStride: Int,
    vRowStride: Int,
    uPixelStride: Int,
    vPixelStride: Int,
    destination: ByteArray
) {
    val chromaWidth = width / 2
    val chromaHeight = height / 2

    var destinationIndex = width * height
    var uSourceRowStart = 0
    var vSourceRowStart = 0

    repeat(chromaHeight) {
        var uSourceIndex = uSourceRowStart
        var vSourceIndex = vSourceRowStart

        if (uPixelStride == 1 && vPixelStride == 1) {
            repeat(chromaWidth) {
                destination[destinationIndex++] = vBuffer.get(vSourceIndex)
                destination[destinationIndex++] = uBuffer.get(uSourceIndex)
                vSourceIndex += 1
                uSourceIndex += 1
            }
        } else {
            repeat(chromaWidth) {
                destination[destinationIndex++] = vBuffer.get(vSourceIndex)
                destination[destinationIndex++] = uBuffer.get(uSourceIndex)
                vSourceIndex += vPixelStride
                uSourceIndex += uPixelStride
            }
        }

        uSourceRowStart += uRowStride
        vSourceRowStart += vRowStride
    }
}
