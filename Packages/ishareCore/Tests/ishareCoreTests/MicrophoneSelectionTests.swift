import Foundation
import Testing
@testable import ishareCore

struct MicrophoneSelectionTests {
    @Test func usesTheConfiguredMicrophoneWhenConnected() {
        let selection = MicrophoneSelection.resolve(configuredID: "usb", connectedIDs: ["builtin", "usb"])
        #expect(selection == .configured("usb"))
        #expect(selection.deviceID == "usb")
        #expect(!selection.fellBackToDefault)
    }

    @Test func fallsBackToTheDefaultWhenTheConfiguredOneIsMissing() {
        let selection = MicrophoneSelection.resolve(configuredID: "usb", connectedIDs: ["builtin"])
        #expect(selection == .missing("usb"))
        #expect(selection.deviceID == nil)
        #expect(selection.fellBackToDefault)
    }

    @Test func usesTheDefaultWithoutAChoice() {
        #expect(MicrophoneSelection.resolve(configuredID: nil, connectedIDs: ["builtin"]) == .systemDefault)
        #expect(MicrophoneSelection.resolve(configuredID: "", connectedIDs: []) == .systemDefault)
        #expect(MicrophoneSelection.systemDefault.deviceID == nil)
    }
}
