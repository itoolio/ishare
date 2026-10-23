import AppIntents
import SwiftUI
import WidgetKit

@main
struct ishareWidgets: WidgetBundle {
    var body: some Widget {
        RecentUploadsWidget()
        CaptureRegionWidget()
        if #available(macOS 26.0, *) {
            CaptureRegionControl()
        }
    }
}

struct CaptureRegionIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Region"
    static let description = IntentDescription("Starts a region screenshot with ishare.")
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetSnapshot.captureRegionURL))
    }
}

@available(macOS 26.0, *)
struct CaptureRegionControl: ControlWidget {
    static let kind = "dev.adrian.ishare.widgets.captureRegion.control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: CaptureRegionIntent()) {
                Label(WidgetStrings.captureRegion, systemImage: "rectangle.dashed")
            }
        }
        .displayName(HostLocalization.resource(WidgetStrings.captureRegion))
        .description(HostLocalization.resource(WidgetStrings.captureRegionDescription))
    }
}

struct CaptureRegionWidget: Widget {
    static let kind = "dev.adrian.ishare.widgets.captureRegion"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: StaticProvider()) { _ in
            CaptureRegionWidgetView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(WidgetStrings.captureRegion)
        .description(WidgetStrings.captureRegionDescription)
        .supportedFamilies([.systemSmall])
    }
}

struct StaticProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
    }

    func placeholder(in _: Context) -> Entry { Entry(date: .now) }

    func getSnapshot(in _: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

struct CaptureRegionWidgetView: View {
    var body: some View {
        Button(intent: CaptureRegionIntent()) {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 34, weight: .medium))
                Text(WidgetStrings.captureRegion)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}
