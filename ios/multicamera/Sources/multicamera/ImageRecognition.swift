import CoreVideo
import Vision

struct ImageRecognition {
  private init() {}

  static func recognizeText(
    _ buffer: CVPixelBuffer,
    onResult: @escaping ([String]?) -> Void
  ) {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
    do {
      try handler.perform([request])
    } catch {
      onResult(nil)
      return
    }

    let text = (request.results ?? []).compactMap {
      $0.topCandidates(1).first?.string
    }
    onResult(text)
  }
}
