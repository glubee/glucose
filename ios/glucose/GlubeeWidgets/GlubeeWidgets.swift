//
//  GlubeeWidgets.swift
//  GlubeeWidgets
//
//  빠른 기록 위젯(v5). 누르면 앱이 카메라(glubee://capture) 또는 인슐린 투여 확인(glubee://insulin)으로
//  바로 열린다. 위젯에는 연속일과 글루비 얼굴만 있고 혈당·음식·인슐린 내용은 없다.
//  잠금 화면에는 연속일 위젯(직사각형·원형·한 줄)과 사진/인슐린 원형 버튼을 둘 수 있다.
//  틴트(단색) 모드에서는 색이 빠지므로 버튼을 색이 아닌 아이콘과 글자로 구분한다.
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

    var shortTitle: String {
        switch self {
        case .capture: "사진 찍기"
        case .insulin: "인슐린"
        }
    }

    var systemImage: String {
        switch self {
        case .capture: "camera"
        case .insulin: "syringe"
        }
    }

    /// v5: 사진은 노랑, 인슐린은 연보라
    var fill: Color {
        switch self {
        case .capture: .widgetBrand
        case .insulin: .widgetLavender
        }
    }
}

/// 앱 Assets 색과 같은 값(위젯은 별도 타깃이라 직접 둔다)
private extension Color {
    static let widgetBrand = Color(red: 0xF6 / 255, green: 0xCF / 255, blue: 0x52 / 255)
    static let widgetInk = Color(red: 0x1E / 255, green: 0x24 / 255, blue: 0x2A / 255)
    static let widgetLavender = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x28 / 255, green: 0x21 / 255, blue: 0x2F / 255, alpha: 1)
        : UIColor(red: 0xF7 / 255, green: 0xF0 / 255, blue: 0xFB / 255, alpha: 1) })
    static let widgetText = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xEF / 255, alpha: 1)
        : UIColor(red: 0x1E / 255, green: 0x24 / 255, blue: 0x2A / 255, alpha: 1) })
    static let widgetSub = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xA4 / 255, green: 0xAA / 255, blue: 0xB1 / 255, alpha: 1)
        : UIColor(red: 0x5F / 255, green: 0x66 / 255, blue: 0x70 / 255, alpha: 1) })
}

// MARK: - 타임라인

struct GlubeeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    var face: String { WidgetMood.face(snapshot, at: date) }
}

struct GlubeeProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlubeeEntry {
        GlubeeEntry(date: .now, snapshot: WidgetSnapshot(streak: 12))
    }

    func getSnapshot(in context: Context, completion: @escaping (GlubeeEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : GlubeeEntry(date: .now, snapshot: .load()))
    }

    /// 얼굴은 13시, 마무리 시각, 자정에 바뀔 수 있다. 앱이 값을 바꾸면 앱이 다시 그리게 한다
    func getTimeline(in context: Context, completion: @escaping (Timeline<GlubeeEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshot.load()
        let dates = [now] + WidgetMood.changePoints(after: now, snapshot: snapshot)
        completion(Timeline(entries: dates.map { GlubeeEntry(date: $0, snapshot: snapshot) }, policy: .atEnd))
    }
}

// MARK: - 중간 크기: 얼굴 + 연속일 + 버튼 2개

struct QuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickActionsWidget", provider: GlubeeProvider()) { entry in
            QuickActionsView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("빠른 기록")
        .description("연속일을 보고, 사진 찍기와 인슐린 기록을 한 번에 열어요.")
        .supportedFamilies([.systemMedium])
    }
}

struct QuickActionsView: View {
    let entry: GlubeeEntry

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image("face_\(entry.face)")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("연속").font(.caption).foregroundStyle(Color.widgetSub)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(entry.snapshot.streak)").font(.title.weight(.black)).monospacedDigit()
                        Text("일").font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(Color.widgetText)
                }
                .accessibilityElement(children: .combine)
                Spacer()
            }
            HStack(spacing: 10) {
                ForEach([QuickAction.capture, .insulin], id: \.title) { action in
                    Link(destination: action.url) {
                        Label(action.shortTitle, systemImage: action.systemImage)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(action == .capture ? Color.widgetInk : Color.widgetText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(action.fill, in: RoundedRectangle(cornerRadius: 14))
                            .widgetAccentable()
                    }
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
    StaticConfiguration(kind: kind, provider: GlubeeProvider()) { _ in
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
            VStack(spacing: 8) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .widgetAccentable()
                Text(action.title)
                    .font(.headline)
            }
            .foregroundStyle(action == .capture ? Color.widgetInk : Color.widgetText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(action.fill, for: .widget)
        }
    }
}

// MARK: - 잠금 화면: 글루비 얼굴 + 연속일

struct StreakLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StreakLockWidget", provider: GlubeeProvider()) { entry in
            StreakLockView(entry: entry)
                .widgetURL(entry.face == "anxious" ? URL(string: "glubee://day-close") : nil)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("연속 완성일")
        .description("잠금 화면에서 글루비와 연속일을 봐요.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct StreakLockView: View {
    let entry: GlubeeEntry
    @Environment(\.widgetFamily) private var family

    private var face: Image { Image("face_\(entry.face)_mono") }

    /// 기록 여부와 시각에만 반응한다(혈당·음식·용량 내용 없음)
    private var status: String {
        switch entry.face {
        case "sleep": "쉬어가는 중이에요"
        case "celebrate": "오늘 완성했어요"
        case "anxious": "마무리할 시간이에요"
        case "nag": "오늘 기록이 아직 없어요"
        default:
            if let last = entry.snapshot.lastRecordAt, WidgetMood.calendar.isDate(last, inSameDayAs: entry.date) {
                "오늘도 기록 중이에요"
            } else {
                "오늘도 같이 해요"
            }
        }
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("글루비 연속 \(entry.snapshot.streak)일")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    face.resizable().scaledToFit().frame(width: 26, height: 26)
                        .widgetAccentable()
                    Text("\(entry.snapshot.streak)")
                        .font(.system(size: 15, weight: .black))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("연속 \(entry.snapshot.streak)일")
        default:
            HStack(spacing: 8) {
                face.resizable().scaledToFit().frame(width: 40, height: 40)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("연속").font(.caption.weight(.semibold))
                        Text("\(entry.snapshot.streak)").font(.title2.weight(.black)).monospacedDigit()
                        Text("일").font(.caption.weight(.bold))
                    }
                    .widgetAccentable()
                    Text(status)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
        }
    }
}

#Preview(as: .systemMedium) {
    QuickActionsWidget()
} timeline: {
    GlubeeEntry(date: .now, snapshot: WidgetSnapshot(streak: 12))
}

#Preview(as: .systemSmall) {
    CaptureWidget()
} timeline: {
    GlubeeEntry(date: .now, snapshot: WidgetSnapshot())
}

#Preview(as: .accessoryRectangular) {
    StreakLockWidget()
} timeline: {
    GlubeeEntry(date: .now, snapshot: WidgetSnapshot(streak: 12))
}
