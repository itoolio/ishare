import Defaults
import SwiftUI

struct MenuFavoritesRow: View {
    let commands: [AppCommand]
    let perform: (AppCommand) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                FavoriteTile(command: command) { perform(command) }
                    .menuFocusRing(.favorite(index))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu.favorites")
    }
}

private struct FavoriteTile: View {
    let command: AppCommand
    let action: () -> Void
    @Environment(\.menuMetrics) private var metrics
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: command.symbol)
                    .font(.system(size: 14, weight: Font.Weight.medium.emphasized(contrast)))
                    .frame(height: 17)
                Text(command.title.localized())
                    .font(.system(size: 9, weight: Font.Weight.medium.emphasized(contrast)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity)
            .frame(height: max(36, metrics.tileHeight - 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(ActionTileStyle())
        .help(command.title.localized())
        .contextMenu { FavoriteMenuItems(id: command.id, allowsReordering: true) }
        .accessibilityLabel(command.title.localized())
        .accessibilityIdentifier("menu.favorite.\(command.id)")
    }
}

struct FavoriteMenuItems: View {
    let id: String
    var allowsReordering = false
    @Default(.menuFavorites) private var ids

    private var favorites: MenuFavorites { MenuFavorites(ids) }

    var body: some View {
        if favorites.contains(id) {
            if allowsReordering {
                Button("Move Left".localized()) { MenuFavorites.current = favorites.moving(id, by: -1) }
                    .disabled(favorites.ids.first == id)
                Button("Move Right".localized()) { MenuFavorites.current = favorites.moving(id, by: 1) }
                    .disabled(favorites.ids.last == id)
                Divider()
            }
            Button("Unpin from Favorites".localized()) { MenuFavorites.current = favorites.unpinning(id) }
        } else {
            Button(favorites.isFull ? String(format: "Favorites Are Full (%d)".localized(), MenuFavorites.limit) : "Pin to Favorites".localized()) {
                MenuFavorites.current = favorites.pinning(id)
            }
            .disabled(favorites.isFull)
        }
    }
}

extension View {
    func favoriteContextMenu(_ id: String?) -> some View {
        modifier(FavoriteContextMenu(id: id))
    }

    func menuSectionDropTarget(_ section: MenuSection, enabled: Bool, targeted: Binding<MenuSection?>) -> some View {
        modifier(MenuSectionDropTarget(section: section, enabled: enabled, targeted: targeted))
    }
}

private struct FavoriteContextMenu: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        if let id {
            content.contextMenu { FavoriteMenuItems(id: id) }
        } else {
            content
        }
    }
}

private struct MenuSectionDropTarget: ViewModifier {
    let section: MenuSection
    let enabled: Bool
    @Binding var targeted: MenuSection?

    func body(content: Content) -> some View {
        if enabled {
            content
                .overlay(alignment: .top) {
                    if targeted == section {
                        Capsule()
                            .fill(Color.menuAccent)
                            .frame(height: 3)
                            .offset(y: -6)
                            .allowsHitTesting(false)
                    }
                }
                .dropDestination(for: String.self) { payloads, _ in
                    guard let dragged = payloads.lazy.compactMap(MenuSectionDrag.section(from:)).first, dragged != section else { return false }
                    withMotionAnimation(.snappy(duration: 0.2)) {
                        MenuLayout.current = MenuLayout.current.moving(dragged, onto: section)
                    }
                    return true
                } isTargeted: { isTargeted in
                    if isTargeted {
                        targeted = section
                    } else if targeted == section {
                        targeted = nil
                    }
                }
        } else {
            content
        }
    }
}

struct MenuSectionDragHandle<Label: View>: View {
    let section: MenuSection
    let enabled: Bool
    @ViewBuilder var label: Label
    @State private var isHovered = false

    var body: some View {
        if enabled {
            HStack(spacing: 4) {
                label
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .draggable(MenuSectionDrag.payload(for: section)) {
                Text(section.title.localized())
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.menuAccent))
                    .foregroundStyle(.white)
            }
            .help("Drag to reorder".localized())
            .accessibilityIdentifier("menu.section.\(section.rawValue)")
        } else {
            HStack {
                label
                Spacer(minLength: 0)
            }
        }
    }
}
