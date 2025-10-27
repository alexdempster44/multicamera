import MLKitBarcodeScanning
import MLKitFaceDetection
import MLKitTextRecognition
import MLKitVision

struct ImageRecognition {
    private init() {}

    private static let textRecognizer = TextRecognizer.textRecognizer(
        options: TextRecognizerOptions()
    )
    private static let barcodeScanner = BarcodeScanner.barcodeScanner(
        options: BarcodeScannerOptions()
    )
    private static let faceDetector = FaceDetector.faceDetector(
        options: FaceDetectorOptions()
    )

    static func recognizeImage(
        _ image: UIImage,
        recognizeText: Bool,
        scanBarcodes: Bool,
        detectFaces: Bool,
        onResults: @escaping (Results) -> Void
    ) {
        var text: [String]? = nil
        if recognizeText {
            do {
                let visionImage = VisionImage(image: image)
                let results = try textRecognizer.results(in: visionImage)
                text = results.blocks.map { $0.text }
            } catch (_) {}
        }

        var barcodes: [String]? = nil
        if scanBarcodes {
            do {
                let visionImage = VisionImage(image: image)
                let results = try barcodeScanner.results(in: visionImage)
                barcodes = results.compactMap { $0.rawValue }
            } catch (_) {}
        }

        var face: Bool? = nil
        if detectFaces {
            do {
                let visionImage = VisionImage(image: image)
                let results = try faceDetector.results(in: visionImage)
                face = !results.isEmpty
            } catch (_) {}
        }

        onResults(
            Results(
                text: text,
                barcodes: barcodes,
                face: face
            )
        )
    }

    class Results {
        let text: [String]?
        let barcodes: [String]?
        let face: Bool?

        init(text: [String]?, barcodes: [String]?, face: Bool?) {
            self.text = text
            self.barcodes = barcodes
            self.face = face
        }
    }
}
