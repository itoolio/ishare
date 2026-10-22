import AppKit
import Defaults

struct SharingPreferences: Codable, Defaults.Serializable {
    var airdrop: Bool = false
    var photos: Bool = false
    var messages: Bool = false
    var mail: Bool = false
}

@MainActor
func shareBasedOnPreferences(_ fileURL: URL) {
    NSLog("Processing share preferences for file: %@", fileURL.path)
    let preferences = Defaults[.builtInShare]

    if preferences.airdrop {
        NSLog("Sharing via AirDrop")
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [fileURL])
    }

    if preferences.photos {
        NSLog("Adding to Photos")
        NSSharingService(named: .addToIPhoto)?.perform(withItems: [fileURL])
    }

    if preferences.messages {
        NSLog("Sharing via Messages")
        NSSharingService(named: .composeMessage)?.perform(withItems: [fileURL])
    }

    if preferences.mail {
        NSLog("Sharing via Mail")
        NSSharingService(named: .composeEmail)?.perform(withItems: [fileURL])
    }
}
