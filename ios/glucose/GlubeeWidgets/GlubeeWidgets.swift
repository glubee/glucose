//
//  GlubeeWidgets.swift
//  GlubeeWidgets
//
//  빠른 기록 위젯. 누르면 앱이 카메라(glubee://capture) 또는 인슐린 투여 확인(glubee://insulin)으로
//  바로 열린다(docs/ios-design-v4.md 0장 위젯 구성). 위젯은 앱을 여는 역할만 하고 서버를 부르지 않는다.
//

import SwiftUI
import WidgetKit

enum QuickAction {
    case capture, insulin

    var url: URL {
        switch self {
        case .capture: URL(string: "glubee://capture")!
        case .insulin: URL(string: "glubee://insulin")!
        }
    }

    var title: String {
        switch self {
        case .capture: "사진 찍기"
        case .insulin: "인슐린 기록"
        }
    }

    var systemImage: String {
        switch self {
        case .capture: "camera.fill"
        case .insulin: "syringe.fill"
        }
    }
}

/// 앱 Assets의 색과 같은 값(위젯은 별도 타깃이라 직접 둔다)
private extension Color {
    static let glubeeBrand = Color(red: 0xF6 / 255, green: 0xCF / 255, blue: 0x52 / 255)
    static let glubeeOnBrand = Color(red: 0x1E / 255, green: 0x24 / 255, blue: 0x2A / 255)
}

// MARK: - 타임라인 (내용이 바뀌지 않는 위젯)

struct StaticEntry: TimelineEntry {
    let date: Date
}

struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> StaticEntry { StaticEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (StaticEntry) -> Void) {
        completion(StaticEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StaticEntry>) -> Void) {
        completion(Timeline(entries: [StaticEntry(date: .now)], policy: .never))
    }
}

// MARK: - 중간 크기: 버튼 2개

struct QuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickActionsWidget", provider: StaticProvider()) { _ in
            QuickActionsView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("빠른 기록")
        .description("사진 찍기와 인슐린 기록을 한 번에 열어요.")
        .supportedFamilies([.systemMedium])
    }
}

struct QuickActionsView: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach([QuickAction.capture, .insulin], id: \.title) { action in
                Link(destination: action.url) {
                    VStack(spacing: 8) {
                        Image(systemName: action.systemImage)
                            .font(.title)
                            .widgetAccentable()
                        Text(action.title)
                            .font(.headline)
                    }
                    .foregroundStyle(Color.glubeeOnBrand)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.glubeeBrand, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}

// MARK: - 작은 크기·잠금 화면: 버튼 하나

struct CaptureWidget: Widget {
    var body: some WidgetConfiguration {
        singleActionConfiguration(.capture, kind: "CaptureWidget", description: "누르면 바로 카메라가 열려요.")
    }
}

struct InsulinWidget: Widget {
    var body: some WidgetConfiguration {
        singleActionConfiguration(.insulin, kind: "InsulinWidget", description: "누르면 바로 인슐린 투여 확인이 열려요.")
    }
}

/// small은 누를 수 있는 곳이 하나뿐이라 widgetURL로 연다
private func singleActionConfiguration(_ action: QuickAction, kind: String, description: String) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: StaticProvider()) { _ in
        SingleActionView(action: action)
            .widgetURL(action.url)
    }
    .configurationDisplayName(action.title)
    .description(description)
    .supportedFamilies([.systemSmall, .accessoryCircular])
}

struct SingleActionView: View {
    let action: QuickAction
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: action.systemImage)
                    .font(.title2)
                    .widgetAccentable()
            }
            .accessibilityLabel(action.title)
            .containerBackground(.clear, for: .widget)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: action.systemImage)
                    .font(.largeTitle)
                    .widgetAccentable()
                Spacer()
                Text(action.title)
                    .font(.headline)
                Text("글루비")
                    .font(.caption)
                    .opacity(0.7)
            }
            .foregroundStyle(Color.glubeeOnBrand)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(Color.glubeeBrand, for: .widget)
        }
    }
}

#Preview(as: .systemMedium) {
    QuickActionsWidget()
} timeline: {
    StaticEntry(date: .now)
}

#Preview(as: .systemSmall) {
    CaptureWidget()
} timeline: {
    StaticEntry(date: .now)
}
