package my.alexl.multicamera

import android.graphics.Bitmap
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

object ImageRecognition {
    private val textRecognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    private val barcodeScanner = BarcodeScanning.getClient(BarcodeScannerOptions.Builder().build())
    private val faceDetector = FaceDetection.getClient(FaceDetectorOptions.Builder().build())

    fun recognizeImage(
        bitmap: Bitmap,
        recognizeText: Boolean,
        scanBarcodes: Boolean,
        detectFaces: Boolean,
        onResults: (Results) -> Unit
    ) {
        val image = InputImage.fromBitmap(bitmap, 0)

        var text: List<String>? = null
        var barcodes: List<String>? = null
        var face: Boolean? = null

        fun checkComplete() {
            if (recognizeText && text == null) return
            if (scanBarcodes && barcodes == null) return
            if (detectFaces && face == null) return

            onResults(Results(text, barcodes, face))
        }

        if (recognizeText) {
            textRecognizer.process(image).addOnSuccessListener { result ->
                text = result.textBlocks.map { it.text }
                checkComplete()
            }
        }

        if (scanBarcodes) {
            barcodeScanner.process(image).addOnSuccessListener { result ->
                barcodes = result.mapNotNull { it.rawValue }
                checkComplete()
            }
        }

        if (detectFaces) {
            faceDetector.process(image).addOnSuccessListener { result ->
                face = result.isNotEmpty()
                checkComplete()
            }
        }
    }

    data class Results(
        val text: List<String>?,
        val barcodes: List<String>?,
        val face: Boolean?
    )
}
