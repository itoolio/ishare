import SwiftUI

struct MenuSectionView<Accessory: View, Content: View>: View {
    let title: String
    let section: MenuSection
    let isPreview: Bool
    let accessory: Accessory
    let content: Content
    @Environment(\.menuMetrics) private var metrics

    init(
        _ title: String,
        section: MenuSection,
        isPreview: Bool,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.section = section
        self.isPreview = isPreview
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            HStack {
                MenuSectionDragHandle(section: section, enabled: !isPreview) {
                    MenuSectionTitle(title: title)
                }
                accessory
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
