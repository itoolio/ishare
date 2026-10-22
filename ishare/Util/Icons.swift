import AppKit

@MainActor
private func resizedAsset(named name: String, width: CGFloat) -> NSImage {
    guard let source = NSImage(named: name), source.size.width > 0 else { return NSImage() }
    let size = NSSize(width: width, height: width * source.size.height / source.size.width)
    return NSImage(size: size, flipped: false) { rect in
        source.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        return true
    }
}

@MainActor let AppIcon = resizedAsset(named: "AppIcon", width: 18)

@MainActor let ImgurIcon = resizedAsset(named: "Imgur", width: 18)

@MainActor let ToastIcon = resizedAsset(named: "AppIcon", width: 100)

@MainActor
func icon(forAppWithName appName: String) -> NSImage? {
    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName) {
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
    return nil
}

let airdropIconPath = Bundle.path(forResource: "AirDrop", ofType: "icns", inDirectory: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources")

@MainActor let airdropIcon = NSImage(contentsOfFile: airdropIconPath!)
