import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let noKeybind = Self("noKeybind")
    static let toggleMainMenu = Self("toggleMainMenu", default: .init(.s, modifiers: [.option, .command]))
    static let captureRegion = Self("captureRegion", default: .init(.p, modifiers: [.option, .command]))
    static let captureWindow = Self("captureWindow", default: .init(.p, modifiers: [.control, .option]))
    static let captureScreen = Self("captureScreen", default: .init(.x, modifiers: [.option, .command]))
    static let recordScreen = Self("recordScreen", default: .init(.z, modifiers: [.control, .option]))
    static let recordGif = Self("recordGif", default: .init(.g, modifiers: [.control, .option]))
    static let openHistoryWindow = Self("openHistoryWindow", default: .init(.k, modifiers: [.command, .option]))
    static let openMostRecentItem = Self("openMostRecentItem", default: .init(.o, modifiers: [.control, .option]))
    static let uploadPasteBoardItem = Self("uploadPasteBoardItem", default: .init(.u, modifiers: [.control, .option]))
    static let captureRegionForceUpload = Self("captureRegionForceUpload", default: .init(.p, modifiers: [.shift, .option, .command]))
    static let captureWindowForceUpload = Self("captureWindowForceUpload", default: .init(.p, modifiers: [.shift, .control, .option]))
    static let captureScreenForceUpload = Self("captureScreenForceUpload", default: .init(.x, modifiers: [.shift, .option, .command]))
    static let recordScreenForceUpload = Self("recordScreenForceUpload", default: .init(.z, modifiers: [.shift, .control, .option]))
    static let recordGifForceUpload = Self("recordGifForceUpload", default: .init(.g, modifiers: [.shift, .control, .option]))
    static let captureScrolling = Self("captureScrolling", default: .init(.s, modifiers: [.control, .option]))
    static let captureLastRegion = Self("captureLastRegion")
    static let recordRegion = Self("recordRegion", default: .init(.r, modifiers: [.control, .option]))
    static let recordRegionGif = Self("recordRegionGif", default: .init(.f, modifiers: [.control, .option]))
    static let openEditor = Self("openEditor", default: .init(.e, modifiers: [.control, .option]))
}
