import AppKit
import Foundation
import SwiftUI

@MainActor
final class UploadManager {
    static let shared = UploadManager()
    private var statusItem: NSStatusItem?
    private var hostingView: NSHostingView<CircularProgressView>?
    private var activeUploads = 0

    private init() {}

    func begin() {
        activeUploads += 1
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let view = NSHostingView(rootView: CircularProgressView(progress: 0))
            let size: CGFloat = 18
            view.frame = CGRect(
                x: (button.bounds.width - size) / 2, y: (button.bounds.height - size) / 2, width: size, height: size
            )
            button.addSubview(view)
            hostingView = view
        }
        statusItem = item
    }

    func updateProgress(fraction: Double) {
        hostingView?.rootView = CircularProgressView(progress: fraction)
    }

    func uploadCompleted() {
        activeUploads = max(0, activeUploads - 1)
        guard activeUploads == 0, let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
        hostingView = nil
    }
}

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 2.0)
                .opacity(0.3)
                .foregroundStyle(.gray)

            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear, value: progress)
        }
        .frame(width: 14, height: 14)
    }
}
