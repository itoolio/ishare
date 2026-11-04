import CoreGraphics
import Foundation

public enum ChildWindowPlan {
    public static let reach: CGFloat = 48
    public static let shadowMargin: CGFloat = 40

    public static func related(to main: WindowDescriptor, in windows: [WindowDescriptor]) -> [WindowDescriptor] {
        guard let pid = main.ownerPID else { return [] }
        let area = main.frame.insetBy(dx: -reach, dy: -reach)
        return windows.filter { window in
            window.id != main.id && window.ownerPID == pid && window.isOnScreen && window.layer >= 0 && window.layer < 1000
                && window.frame.width >= 8 && window.frame.height >= 8 && area.intersects(window.frame)
                && window.frame.width * window.frame.height < main.frame.width * main.frame.height * 4
        }
    }

    public static func captureRect(main: CGRect, related: [CGRect], within display: CGRect, includesShadow: Bool) -> CGRect {
        let union = related.reduce(main) { $0.union($1) }
        let padded = includesShadow ? union.insetBy(dx: -shadowMargin, dy: -shadowMargin) : union
        return padded.intersection(display).integral
    }
}
