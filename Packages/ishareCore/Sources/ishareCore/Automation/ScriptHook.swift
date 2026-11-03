import Foundation

public enum ScriptHookEvent: String, CaseIterable, Sendable {
    case capture
    case recording
    case upload
}

public struct ScriptHookInvocation: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]

    public static let shell = "/bin/zsh"

    public static func make(script: String, event: ScriptHookEvent, file: String, link: String?, isExecutable: Bool) -> ScriptHookInvocation {
        let values = [event.rawValue, file] + (link.map { [$0] } ?? [])
        var environment = ["ISHARE_EVENT": event.rawValue, "ISHARE_FILE": file]
        environment["ISHARE_LINK"] = link
        if isExecutable {
            return ScriptHookInvocation(executable: script, arguments: values, environment: environment)
        }
        return ScriptHookInvocation(executable: shell, arguments: [script] + values, environment: environment)
    }
}
