import CoreGraphics

public enum FaceRedactionLayout {
    public static let defaultPadding: CGFloat = 0.2

    public static func rects(forNormalized boxes: [CGRect], imageSize: CGSize, padding: CGFloat = defaultPadding) -> [CGRect] {
        let bounds = CGRect(origin: .zero, size: imageSize)
        return boxes.compactMap { box in
            let rect = CGRect(
                x: box.minX * imageSize.width,
                y: (1 - box.maxY) * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            )
            let padded = rect.insetBy(dx: -rect.width * padding, dy: -rect.height * padding).intersection(bounds).integral
            return padded.isNull || padded.width < 2 || padded.height < 2 ? nil : padded
        }
    }
}
