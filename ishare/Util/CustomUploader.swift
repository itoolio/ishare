import Defaults
import ishareCore

extension CustomUploader: @retroactive CaseIterable, @retroactive Defaults.Serializable {
    public static var allCases: [CustomUploader] {
        (Defaults[.savedCustomUploaders] ?? []).union(Defaults[.savedLocalUploaders])
            .sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
}
