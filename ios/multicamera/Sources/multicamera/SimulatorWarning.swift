#if targetEnvironment(simulator)
  import UIKit

  enum SimulatorWarning {
    private static let size = CGSize(width: 1920, height: 1080)
    private static let jpegQuality: CGFloat = 0.8

    private static var images: [Camera.Direction: UIImage] = [:]
    private static var buffers: [Camera.Direction: CVPixelBuffer] = [:]
    private static var data: [Camera.Direction: Data] = [:]

    static func pixelBuffer(for direction: Camera.Direction) -> CVPixelBuffer? {
      if let buffer = buffers[direction] { return buffer }
      guard let buffer = makePixelBuffer(for: direction) else { return nil }
      buffers[direction] = buffer
      return buffer
    }

    static func imageData(for direction: Camera.Direction) -> Data? {
      if let data = data[direction] { return data }
      guard
        let encoded = image(for: direction).jpegData(
          compressionQuality: jpegQuality
        )
      else { return nil }
      data[direction] = encoded
      return encoded
    }

    private static func image(for direction: Camera.Direction) -> UIImage {
      if let image = images[direction] { return image }
      let image =
        Thread.isMainThread
        ? makeImage(for: direction)
        : DispatchQueue.main.sync { makeImage(for: direction) }
      images[direction] = image
      return image
    }

    private static func makePixelBuffer(
      for direction: Camera.Direction
    ) -> CVPixelBuffer? {
      guard let cgImage = image(for: direction).cgImage else { return nil }
      let width = cgImage.width
      let height = cgImage.height

      var pixelBuffer: CVPixelBuffer?
      let attributes: [CFString: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey: [:],
        kCVPixelBufferMetalCompatibilityKey: true,
      ]
      let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attributes as CFDictionary,
        &pixelBuffer
      )
      guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
        return nil
      }

      CVPixelBufferLockBaseAddress(buffer, [])
      defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

      guard
        let context = CGContext(
          data: CVPixelBufferGetBaseAddress(buffer),
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        )
      else { return nil }

      context.draw(
        cgImage,
        in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
      )
      return buffer
    }

    private static func makeImage(for direction: Camera.Direction) -> UIImage {
      let bounds = CGRect(origin: .zero, size: size)
      let hueRange: ClosedRange<CGFloat> =
        direction == .back ? 140...300 : 20...160
      let cameraSymbol =
        direction == .back ? "photo.fill" : "person.crop.rectangle.fill"
      let scale = size.height / 720
      let renderer = UIGraphicsImageRenderer(size: size)
      return renderer.image { context in
        let cg = context.cgContext

        let stops = 24
        let colors =
          (0...stops).map { step -> CGColor in
            let hue =
              hueRange.lowerBound
              + (hueRange.upperBound - hueRange.lowerBound)
              * CGFloat(step) / CGFloat(stops)
            return oklch(lightness: 0.72, chroma: 0.15, hue: hue).cgColor
          } as CFArray
        let locations = (0...stops).map { CGFloat($0) / CGFloat(stops) }
        if let gradient = CGGradient(
          colorsSpace: CGColorSpaceCreateDeviceRGB(),
          colors: colors,
          locations: locations
        ) {
          cg.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: size.width, y: size.height),
            options: []
          )
        }

        UIColor(white: 1, alpha: 0.5).setStroke()
        let diagonals = UIBezierPath()
        diagonals.lineWidth = 4 * scale
        diagonals.move(to: .zero)
        diagonals.addLine(to: CGPoint(x: size.width, y: size.height))
        diagonals.move(to: CGPoint(x: size.width, y: 0))
        diagonals.addLine(to: CGPoint(x: 0, y: size.height))
        diagonals.stroke()

        let bandWidth = size.height * 0.06
        let bandHeight = size.height * 0.6
        let band = CGRect(
          x: size.width * 0.2 - bandWidth / 2,
          y: (size.height - bandHeight) / 2,
          width: bandWidth,
          height: bandHeight
        )
        cg.saveGState()
        cg.clip(to: band)
        if let grayscale = CGGradient(
          colorsSpace: CGColorSpaceCreateDeviceRGB(),
          colors: [UIColor.white.cgColor, UIColor.black.cgColor] as CFArray,
          locations: [0, 1]
        ) {
          cg.drawLinearGradient(
            grayscale,
            start: CGPoint(x: band.midX, y: band.minY),
            end: CGPoint(x: band.midX, y: band.maxY),
            options: []
          )
        }
        cg.restoreGState()

        let ring = UIBezierPath(
          arcCenter: CGPoint(x: size.width / 2, y: size.height / 2),
          radius: size.height / 4,
          startAngle: 0,
          endAngle: .pi * 2,
          clockwise: true
        )
        ring.lineWidth = 4 * scale
        ring.stroke()

        let borderWidth: CGFloat = 4 * scale
        UIColor.white.setStroke()
        let border = UIBezierPath(
          rect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        )
        border.lineWidth = borderWidth
        border.stroke()

        func drawSymbol(
          _ name: String,
          pointSize: CGFloat,
          color: UIColor,
          center: CGPoint
        ) {
          let config = UIImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .semibold
          )
          guard
            let symbol = UIImage(systemName: name, withConfiguration: config)?
              .withTintColor(color, renderingMode: .alwaysOriginal)
          else { return }
          symbol.draw(
            at: CGPoint(
              x: center.x - symbol.size.width / 2,
              y: center.y - symbol.size.height / 2
            )
          )
        }

        drawSymbol(
          cameraSymbol,
          pointSize: 200 * scale,
          color: .white,
          center: CGPoint(x: size.width / 2, y: size.height / 2)
        )
        drawSymbol(
          "exclamationmark.triangle.fill",
          pointSize: 90 * scale,
          color: .systemYellow,
          center: CGPoint(x: size.width / 2, y: size.height * 0.16)
        )
      }
    }

    private static func oklch(
      lightness: CGFloat,
      chroma: CGFloat,
      hue: CGFloat
    ) -> UIColor {
      let radians = hue * .pi / 180
      let a = chroma * cos(radians)
      let b = chroma * sin(radians)

      let lRoot = lightness + 0.3963377774 * a + 0.2158037573 * b
      let mRoot = lightness - 0.1055613458 * a - 0.0638541728 * b
      let sRoot = lightness - 0.0894841775 * a - 1.2914855480 * b

      let l = lRoot * lRoot * lRoot
      let m = mRoot * mRoot * mRoot
      let s = sRoot * sRoot * sRoot

      let red = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
      let green = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
      let blue = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

      func encode(_ value: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, value))
        return clamped <= 0.0031308
          ? 12.92 * clamped
          : 1.055 * pow(clamped, 1 / 2.4) - 0.055
      }

      return UIColor(
        red: encode(red),
        green: encode(green),
        blue: encode(blue),
        alpha: 1
      )
    }
  }
#endif
