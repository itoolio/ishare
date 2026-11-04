import BezelNotification
import Defaults
import ishareCore

@MainActor
enum CaptureAgain {
    static func remember(_ recipe: CaptureRecipe) {
        Defaults[.lastCaptureRecipe] = recipe
    }

    static var last: CaptureRecipe? {
        Defaults[.lastCaptureRecipe]
    }

    static func run(options: CaptureOptions = .standard) async {
        guard let recipe = last else {
            BezelNotification.show(messageText: "Take a capture first".localized(), icon: ToastIcon)
            return
        }
        Log.capture.info("Capturing again: \(recipe.kind, privacy: .public)")
        switch recipe {
        case let .appWindows(bundleID, contactSheet):
            guard let pid = await AppWindowsCapture.resolveApp(bundleID) else {
                BezelNotification.show(messageText: "The app from the last capture isn’t open".localized(), icon: ToastIcon)
                return
            }
            await AppWindowsCapture.capture(pid: pid, as: contactSheet ? .contactSheet : .separate, options: options)
        case let .webPage(address, width, pdf, dismisses):
            await WebPageCaptureFlow.capture(
                WebPageCaptureRequest(address: address, width: width, format: pdf ? .pdf : .image, dismissesCookieBanners: dismisses), options: options)
        default:
            guard let captured = await ImageCaptureFlow.captureAgain(recipe) else {
                BezelNotification.show(messageText: "The last capture can’t be repeated".localized(), icon: ToastIcon)
                return
            }
            await CaptureSession.deliverCapture(captured, options: options)
        }
    }
}
