import CoreGraphics
import Foundation

public enum WebcamLayout: String, CaseIterable, Codable, Hashable, Sendable {
    case bubble
    case sideBySide
    case fullScreenAtMarkers

    public static let sideBySideFraction: CGFloat = 0.28
    public static let fullScreenDuration = 3.0
}

public struct WebcamPlacement: Equatable, Sendable {
    public var screen: CGRect
    public var webcam: CGRect
    public var isRound: Bool
    public var webcamOnTop: Bool
}

public enum WebcamLayoutPlanner {
    public static func placement(
        layout: WebcamLayout, videoSize: CGSize, sourceSize: CGSize, bubble: CGRect, time: Double, sections: [Double]
    ) -> WebcamPlacement {
        let full = CGRect(origin: .zero, size: videoSize)
        switch layout {
        case .bubble:
            return WebcamPlacement(screen: full, webcam: bubble, isRound: true, webcamOnTop: true)
        case .sideBySide:
            let column = (videoSize.width * WebcamLayout.sideBySideFraction).rounded()
            let screenArea = CGRect(x: 0, y: 0, width: videoSize.width - column, height: videoSize.height)
            return WebcamPlacement(
                screen: fitted(sourceSize, in: screenArea), webcam: CGRect(x: screenArea.maxX, y: 0, width: column, height: videoSize.height), isRound: false,
                webcamOnTop: true)
        case .fullScreenAtMarkers:
            let showsFull = sections.contains { time >= $0 && time < $0 + WebcamLayout.fullScreenDuration }
            return showsFull
                ? WebcamPlacement(screen: full, webcam: full, isRound: false, webcamOnTop: true)
                : WebcamPlacement(screen: full, webcam: bubble, isRound: true, webcamOnTop: true)
        }
    }

    public static func fitted(_ size: CGSize, in area: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return area }
        let scale = min(area.width / size.width, area.height / size.height)
        let fitted = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return CGRect(x: (area.midX - fitted.width / 2).rounded(), y: (area.midY - fitted.height / 2).rounded(), width: fitted.width, height: fitted.height)
    }
}
