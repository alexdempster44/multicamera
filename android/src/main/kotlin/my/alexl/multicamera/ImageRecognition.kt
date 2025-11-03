package my.alexl.multicamera

import android.media.Image
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
        image: Image,
        recognizeText: Boolean,
        scanBarcodes: Boolean,
        detectFaces: Boolean,
        onResults: (Results) -> Unit
    ) {
        var recognizeText = recognizeText
        var scanBarcodes = scanBarcodes
        var detectFaces = detectFaces

        val inputImage = InputImage.fromMediaImage(image, 0)

        var text: List<String>? = null
        var barcodes: List<String>? = null
        var face: Boolean? = null

        fun checkComplete() {
            if (recognizeText && text == null) return
            if (scanBarcodes && barcodes == null) return
            if (detectFaces && face == null) return

            image.close()
            onResults(Results(text, barcodes, face))
        }

        if (recognizeText) {
            textRecognizer.process(inputImage).addOnSuccessListener { result ->
                text = result.textBlocks.map { it.text }
                checkComplete()
            }.addOnFailureListener {
                recognizeText = false
                checkComplete()
            }
        }
        if (scanBarcodes) {
            barcodeScanner.process(inputImage).addOnSuccessListener { result ->
                barcodes = result.mapNotNull { it.rawValue }
                checkComplete()
            }.addOnFailureListener {
                scanBarcodes = false
                checkComplete()
            }
        }
        if (detectFaces) {
            faceDetector.process(inputImage).addOnSuccessListener { result ->
                face = result.isNotEmpty()
                checkComplete()
            }.addOnFailureListener {
                detectFaces = false
                checkComplete()
            }
        }

        checkComplete()
    }

    data class Results(
        val text: List<String>?,
        val barcodes: List<String>?,
        val face: Boolean?
    )
}
