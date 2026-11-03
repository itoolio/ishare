import AppKit
import Foundation

enum ScriptingCodes {
    static func fourCharCode(_ value: String) -> FourCharCode {
        value.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    static func captureMode(_ code: FourCharCode?) -> CLICaptureMode? {
        switch code {
        case nil: .region
        case fourCharCode("cReg"): .region
        case fourCharCode("cWin"): .window
        case fourCharCode("cScr"): .screen
        case fourCharCode("cScl"): .scrolling
        case fourCharCode("cMnu"): .menu
        default: nil
        }
    }

    static func recordAction(_ code: FourCharCode?) -> CLIRecordAction? {
        switch code {
        case nil: .toggle
        case fourCharCode("rSta"): .start
        case fourCharCode("rSto"): .stop
        case fourCharCode("rTog"): .toggle
        case fourCharCode("rPau"): .pause
        case fourCharCode("rRes"): .resume
        default: nil
        }
    }

    static func openTarget(_ code: FourCharCode?) -> AutomationOpenTarget? {
        switch code {
        case fourCharCode("oHis"): .history
        case fourCharCode("oSet"): .settings(nil)
        case fourCharCode("oEdi"): .editor
        default: nil
        }
    }

    static func code(of parameter: Any?) -> FourCharCode? {
        (parameter as? NSNumber)?.uint32Value
    }
}

struct PendingScriptCommand: @unchecked Sendable {
    let command: AsyncScriptCommand
}

class AsyncScriptCommand: NSScriptCommand, @unchecked Sendable {
    func fail(_ message: String) {
        scriptErrorNumber = Int(errAEEventFailed)
        scriptErrorString = message
    }

    func runAsync(_ work: @escaping @MainActor (AsyncScriptCommand) async -> Any?) {
        suspendExecution()
        let pending = PendingScriptCommand(command: self)
        Task { @MainActor in
            let result = await work(pending.command)
            pending.command.resumeExecution(withResult: result)
        }
    }

    @MainActor var actions: any AutomationActions {
        URLSchemeRouter.shared.actions
    }

}

@objc(ScriptCaptureCommand)
final class ScriptCaptureCommand: AsyncScriptCommand, @unchecked Sendable {
    override func performDefaultImplementation() -> Any? {
        guard let mode = ScriptingCodes.captureMode(ScriptingCodes.code(of: directParameter)) else {
            fail("Unknown capture mode".localized())
            return nil
        }
        let upload = evaluatedArguments?["upload"] as? Bool ?? false
        runAsync { command in
            switch await command.actions.capture(mode, upload: upload) {
            case let .success(result):
                return result.link ?? result.file ?? ""
            case let .failure(error):
                command.fail(error.message)
                return nil
            }
        }
        return nil
    }
}

@objc(ScriptUploadCommand)
final class ScriptUploadCommand: AsyncScriptCommand, @unchecked Sendable {
    override func performDefaultImplementation() -> Any? {
        let files = ((directParameter as? [Any]) ?? [directParameter as Any]).compactMap { $0 as? URL }
        guard !files.isEmpty else {
            fail("Choose at least one file to upload".localized())
            return nil
        }
        let uploader = evaluatedArguments?["uploader"] as? String
        runAsync { command in
            let results = await command.actions.upload(files, uploader: uploader)
            if results.allSatisfy({ $0.link == nil }), let error = results.first(where: { $0.error != nil })?.error {
                command.fail(error)
                return nil
            }
            return results.compactMap(\.link)
        }
        return nil
    }
}

@objc(ScriptRecordCommand)
final class ScriptRecordCommand: AsyncScriptCommand, @unchecked Sendable {
    override func performDefaultImplementation() -> Any? {
        guard let action = ScriptingCodes.recordAction(ScriptingCodes.code(of: directParameter)) else {
            fail("Unknown recording action".localized())
            return nil
        }
        let preset = evaluatedArguments?["preset"] as? String
        runAsync { command in
            switch await command.actions.record(action, gif: false, region: false, preset: preset) {
            case let .success(recording):
                return recording
            case let .failure(error):
                command.fail(error.message)
                return nil
            }
        }
        return nil
    }
}

@objc(ScriptSelectUploaderCommand)
final class ScriptSelectUploaderCommand: AsyncScriptCommand, @unchecked Sendable {
    override func performDefaultImplementation() -> Any? {
        guard let name = directParameter as? String else {
            fail("Name an uploader".localized())
            return nil
        }
        let selected: Bool = MainActor.assumeIsolated { URLSchemeRouter.shared.actions.selectUploader(named: name) }
        if !selected {
            fail(String(format: "No uploader named “%@”".localized(), name))
        }
        return selected
    }
}

@objc(ScriptShowCommand)
final class ScriptShowCommand: AsyncScriptCommand, @unchecked Sendable {
    override func performDefaultImplementation() -> Any? {
        guard let target = ScriptingCodes.openTarget(ScriptingCodes.code(of: directParameter)) else {
            fail("Unknown window".localized())
            return nil
        }
        MainActor.assumeIsolated { URLSchemeRouter.shared.actions.open(target) }
        return nil
    }
}

@objc(ScriptableHistoryItem)
final class ScriptableHistoryItem: NSObject, Sendable {
    @objc let id: String
    @objc let link: String
    @objc let title: String
    @objc let uploadDate: Date?
    @objc let uploaderName: String
    @objc let altText: String
    @objc let localFile: String

    init(_ entry: CLIHistoryEntry) {
        link = entry.shortLink ?? entry.link ?? ""
        id = entry.link ?? entry.localPath ?? UUID().uuidString
        title = entry.title
        uploadDate = entry.date
        uploaderName = entry.uploader ?? ""
        altText = entry.altText ?? ""
        localFile = entry.localPath ?? ""
    }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let description = NSScriptClassDescription(for: NSApplication.self) else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: description, containerSpecifier: nil, key: "scriptingHistoryItems", uniqueID: id)
    }
}

@objc(ScriptableUploader)
final class ScriptableUploader: NSObject, Sendable {
    @objc let id: String
    @objc let name: String
    @objc let kind: String
    @objc let isDefault: Bool

    init(_ info: CLIUploaderInfo) {
        id = info.id
        name = info.name
        kind = info.kind
        isDefault = info.selected
    }

    @objc var `default`: Bool { isDefault }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let description = NSScriptClassDescription(for: NSApplication.self) else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: description, containerSpecifier: nil, key: "scriptingUploaders", uniqueID: id)
    }
}

extension NSApplication {
    @objc var scriptingHistoryItems: [ScriptableHistoryItem] {
        MainActor.assumeIsolated { URLSchemeRouter.shared.actions.history(limit: 200).map(ScriptableHistoryItem.init) }
    }

    @objc var scriptingUploaders: [ScriptableUploader] {
        MainActor.assumeIsolated { URLSchemeRouter.shared.actions.uploaders().map(ScriptableUploader.init) }
    }
}
