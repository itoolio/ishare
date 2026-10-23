import AppKit
import Foundation

enum HostApp {
    static var executableURL: URL? {
        Bundle.main.executableURL?.resolvingSymlinksInPath()
    }

    static var bundleURL: URL? {
        if let executable = executableURL {
            let candidate = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            if candidate.pathExtension == "app" {
                return candidate
            }
        }
        return CLIAppGroup.bundleIdentifiers.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    static var version: String {
        guard let url = bundleURL, let bundle = Bundle(url: url),
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return "unknown" }
        return version
    }

    static func open(_ url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        if let app = bundleURL {
            do {
                _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
                return
            } catch {
                FileHandle.standardError.write(Data("ishare: opening \(app.path) failed, trying the default app: \(error.localizedDescription)\n".utf8))
            }
        }
        try openWithLaunchServices(url)
    }

    private static func openWithLaunchServices(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", url.absoluteString]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIProtocolError.launchFailed("open exited with status \(process.terminationStatus); is ishare installed?")
        }
    }
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data("ishare: \(message)\n".utf8))
}

func run() async -> Int32 {
    let action: CLIAction
    do {
        action = try CLIArguments.parse(Array(CommandLine.arguments.dropFirst()))
    } catch {
        printError(error.description)
        FileHandle.standardError.write(Data("\n\(CLIArguments.usage)\n".utf8))
        return 2
    }
    switch action {
    case let .help(text):
        print(text)
        return 0
    case .version:
        print(HostApp.version)
        return 0
    case let .run(invocation):
        guard let directory = CLIAppGroup.mailboxDirectory else {
            printError(CLIProtocolError.noMailbox.description)
            return 1
        }
        let client = CLIClient(mailbox: CLIMailbox(directory: directory), launch: { try await HostApp.open($0) })
        do {
            let response = try await client.send(invocation.command, timeout: invocation.timeout)
            if invocation.json {
                print(CLIOutput.json(for: response))
            } else {
                let text = CLIOutput.text(for: response, command: invocation.command)
                if !text.isEmpty {
                    print(text)
                }
            }
            if !invocation.json || !response.success {
                CLIOutput.errors(for: response).forEach(printError)
            }
            return CLIOutput.exitCode(for: response)
        } catch let error as CLIProtocolError {
            printError(error.description)
            if case .timedOut = error { return 3 }
            return 1
        } catch {
            printError(error.localizedDescription)
            return 1
        }
    }
}

exit(await run())
