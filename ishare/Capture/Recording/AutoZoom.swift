import CoreGraphics
import Defaults
import Foundation
import ishareCore

extension AutoZoomSettings {
    static var current: AutoZoomSettings {
        AutoZoomSettings(
            zoom: Defaults[.autoZoomLevel],
            easeDuration: Defaults[.autoZoomEaseDuration],
            holdTime: Defaults[.autoZoomHoldTime],
            followsPointer: Defaults[.autoZoomFollowsPointer]
        )
    }
}
