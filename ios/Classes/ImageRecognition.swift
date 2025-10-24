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
        let orientation = image.imageOrientation
        let image = VisionImage(image: image)
        image.orientation = orientation

        Task {
            do {
                var text: [String]? = nil
                if recognizeText {
                    let results = try textRecognizer.results(in: image)
                    text = results.blocks.map { $0.text }
                }

                var barcodes: [String]? = nil
                if scanBarcodes {
                    let results = try barcodeScanner.results(in: image)
                    barcodes = results.compactMap { $0.rawValue }
                }

                var face: Bool? = nil
                if detectFaces {
                    let results = try faceDetector.results(in: image)
                    face = !results.isEmpty
                }

                onResults(
                    Results(
                        text: text,
                        barcodes: barcodes,
                        face: face
                    )
                )
            } catch (_) {}
        }
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
