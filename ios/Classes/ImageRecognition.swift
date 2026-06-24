import UIKit
import Vision

struct ImageRecognition {
  private init() {}

  static func recognizeImage(
    _ image: UIImage,
    recognizeText: Bool,
    scanBarcodes: Bool,
    detectFaces: Bool,
    onResults: @escaping (Results) -> Void
  ) {
    guard let cgImage = image.cgImage else {
      onResults(Results(text: nil, barcodes: nil, face: nil))
      return
    }

    var requests: [VNRequest] = []

    var textRequest: VNRecognizeTextRequest? = nil
    if recognizeText {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      requests.append(request)
      textRequest = request
    }

    var barcodeRequest: VNDetectBarcodesRequest? = nil
    if scanBarcodes {
      let request = VNDetectBarcodesRequest()
      requests.append(request)
      barcodeRequest = request
    }

    var faceRequest: VNDetectFaceRectanglesRequest? = nil
    if detectFaces {
      let request = VNDetectFaceRectanglesRequest()
      requests.append(request)
      faceRequest = request
    }

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform(requests)
    } catch {
      onResults(Results(text: nil, barcodes: nil, face: nil))
      return
    }

    let text = textRequest.map { request in
      (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
    let barcodes = barcodeRequest.map { request in
      (request.results ?? []).compactMap { $0.payloadStringValue }
    }
    let face = faceRequest.map { !($0.results ?? []).isEmpty }

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
