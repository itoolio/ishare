import AppKit
import Defaults
import Foundation

enum MenuSection: String, CaseIterable, Identifiable, Codable, Sendable, Defaults.Serializable {
    case capture
    case record
    case afterCapture
    case recentUploads
    case footer

    var id: Self { self }

    var title: String {
        switch self {
        case .capture: "Capture"
        case .record: "Record"
        case .afterCapture: "After Capture"
        case .recentUploads: "Recent Uploads"
        case .footer: "Footer"
        }
    }

    var symbol: String {
        switch self {
        case .capture: "camera.viewfinder"
        case .record: "record.circle"
        case .afterCapture: "checklist"
        case .recentUploads: "clock.arrow.circlepath"
        case .footer: "rectangle.bottomhalf.filled"
        }
    }
}

struct MenuLayout: Equatable, Sendable {
    var order: [MenuSection]
    var hidden: Set<MenuSection>

    init(order: [MenuSection] = MenuSection.allCases, hidden: Set<MenuSection> = []) {
        self.order = Self.normalized(order)
        self.hidden = hidden
    }

    static func normalized(_ order: [MenuSection]) -> [MenuSection] {
        var seen = Set<MenuSection>()
        let unique = order.filter { seen.insert($0).inserted }
        return unique + MenuSection.allCases.filter { !seen.contains($0) }
    }

    var visibleSections: [MenuSection] {
        order.filter { !hidden.contains($0) }
    }

    func isVisible(_ section: MenuSection) -> Bool {
        !hidden.contains(section)
    }

    func moving(_ section: MenuSection, by offset: Int) -> MenuLayout {
        guard let index = order.firstIndex(of: section) else { return self }
        let destination = min(max(index + offset, 0), order.count - 1)
        guard destination != index else { return self }
        var order = order
        order.remove(at: index)
        order.insert(section, at: destination)
        return MenuLayout(order: order, hidden: hidden)
    }

    func setting(_ section: MenuSection, visible: Bool) -> MenuLayout {
        var hidden = hidden
        if visible {
            hidden.remove(section)
        } else {
            hidden.insert(section)
        }
        return MenuLayout(order: order, hidden: hidden)
    }

    @MainActor static var current: MenuLayout {
        get { MenuLayout(order: Defaults[.menuSectionOrder], hidden: Defaults[.hiddenMenuSections]) }
        set {
            Defaults[.menuSectionOrder] = newValue.order
            Defaults[.hiddenMenuSections] = newValue.hidden
        }
    }
}

enum MenuDensity: String, CaseIterable, Identifiable, Codable, Sendable, Defaults.Serializable {
    case comfortable
    case compact

    var id: Self { self }

    var title: String {
        switch self {
        case .comfortable: "Comfortable"
        case .compact: "Compact"
        }
    }

    var metrics: MenuMetrics {
        switch self {
        case .comfortable: MenuMetrics(stackSpacing: 12, sectionSpacing: 8, padding: 12, tileHeight: 58, tileSymbolSize: 17, tileSpacing: 5, wideHeight: 40, footerHeight: 32, thumbnailSize: 44)
        case .compact: MenuMetrics(stackSpacing: 8, sectionSpacing: 5, padding: 10, tileHeight: 44, tileSymbolSize: 15, tileSpacing: 3, wideHeight: 32, footerHeight: 26, thumbnailSize: 36)
        }
    }
}

struct MenuMetrics: Equatable, Sendable {
    let stackSpacing: CGFloat
    let sectionSpacing: CGFloat
    let padding: CGFloat
    let tileHeight: CGFloat
    let tileSymbolSize: CGFloat
    let tileSpacing: CGFloat
    let wideHeight: CGFloat
    let footerHeight: CGFloat
    let thumbnailSize: CGFloat
}

enum MenuTheme: String, CaseIterable, Identifiable, Codable, Sendable, Defaults.Serializable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }

    @MainActor var appearance: NSAppearance? {
        appearanceName.flatMap(NSAppearance.init(named:))
    }
}

struct MenuContrast: Equatable, Sendable {
    let isHigh: Bool

    static let standard = MenuContrast(isHigh: false)
    static let high = MenuContrast(isHigh: true)

    static func resolve(userPreference: Bool, systemIncreaseContrast: Bool) -> MenuContrast {
        userPreference || systemIncreaseContrast ? .high : .standard
    }

    var fillOpacity: Double { isHigh ? 0.16 : 0.08 }
    var hoverFillOpacity: Double { isHigh ? 0.24 : 0.14 }
    var iconFillOpacity: Double { isHigh ? 0.15 : 0.07 }
    var borderOpacity: Double { isHigh ? 0.45 : 0.12 }
    var borderWidth: CGFloat { isHigh ? 1.5 : 1 }
    var secondaryOpacity: Double { isHigh ? 0.85 : 0.55 }
    var dimmedOpacity: Double { isHigh ? 0.75 : 0.55 }
}

enum ToastCorner: String, CaseIterable, Identifiable, Codable, Sendable, Defaults.Serializable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: Self { self }

    var title: String {
        switch self {
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        }
    }

    var isTop: Bool { self == .topLeft || self == .topRight }
    var isLeading: Bool { self == .topLeft || self == .bottomLeft }
}

enum ToastScreenChoice: String, CaseIterable, Identifiable, Codable, Sendable, Defaults.Serializable {
    case pointer
    case main
    case capturedContent

    var id: Self { self }

    var title: String {
        switch self {
        case .pointer: "Screen with Pointer"
        case .main: "Main Screen"
        case .capturedContent: "Screen of the Captured Content"
        }
    }
}

enum ResultPresentation: String, CaseIterable, Identifiable, Codable, Sendable, Defaults.Serializable {
    case toast
    case notification
    case both

    var id: Self { self }

    var title: String {
        switch self {
        case .toast: "Toast"
        case .notification: "Notification"
        case .both: "Both"
        }
    }

    var showsToast: Bool { self != .notification }
    var postsNotification: Bool { self != .toast }
}
