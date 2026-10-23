import SwiftUI

struct MenuFavoritesSection: View {
    let commands: [AppCommand]
    let isPreview: Bool
    @Environment(\.menuMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            MenuSectionTitle(title: "Favorites")
            MenuFavoritesRow(commands: commands) { command in
                guard !isPreview else { return }
                command.perform()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
