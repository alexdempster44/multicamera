import UIKit
import Vision

struct ImageRecognition {
  private init() {}

  static func recognizeText(
    _ image: UIImage,
    onResult: @escaping ([String]?) -> Void
  ) {
    guard let cgImage = image.cgImage else {
      onResult(nil)
      return
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
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
