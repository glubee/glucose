//
//  ReportSamples.swift
//  glucose
//
//  DEBUG 전용: 실행 인자 -reports -reportSample 이면 서버 대신 예시 값으로 리포트를 그린다(로그인 없이 화면 확인).
//  실제 사용자 데이터가 아니라 손으로 만든 값이다.
//

#if DEBUG
import Foundation
import UIKit

enum ReportSamples {
    static var isEnabled: Bool {
        ["-reportSample", "-dailyReportPreview", "-chartDetail", "-timelineSample", "-timelineEmptySample"].contains { ProcessInfo.processInfo.arguments.contains($0) }
    }

    static func photoID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", index))!
    }

    static func records(_ day: Date) -> [IntakeRecord] {
        let entries = [(8, 10, "현미밥", "공기"), (8, 20, "계란말이", "접시"), (8, 35, "우유", "잔"),
                       (11, 0, "요거트", "개"), (19, 0, "김치찌개", "그릇")]
        return entries.enumerated().map { index, entry in
            IntakeRecord(id: UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", index + 1))!,
                         occurredAt: at(day, entry.0, entry.1), context: index == 3 ? .snack : .meal,
                         items: [FoodItem(id: UUID(), name: entry.2, count: 1, unit: entry.3)], photoId: photoID(index + 1))
        }
    }

    static func record(for mark: DailyReport.Episode.IntakeMark) -> IntakeRecord? {
        records(mark.occurredAt).first {
            $0.occurredAt == mark.occurredAt && $0.photoId == mark.photoId && $0.context == mark.context
        }
    }

    /// 예시 기록마다 음식 이름에 맞는 그림(DemoFoodArt)
    private static let photoImages: [UUID: UIImage] = Dictionary(uniqueKeysWithValues: records(.now).compactMap { record in
        record.photoId.map { ($0, DemoFoodArt.image(foods: record.items.map(\.name))) }
    })

    static func image(for photoId: UUID) -> UIImage? {
        isEnabled ? photoImages[photoId] : nil
    }

    private static func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
        ReportDay.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func daily(_ day: Date) -> (DailyReport, [GlucosePoint]) {
        let records = records(day)
        func mark(_ index: Int) -> DailyReport.Episode.IntakeMark {
            let record = records[index]
            return .init(occurredAt: record.occurredAt, context: record.context, photoId: record.photoId,
                         foods: record.items.map { $0.name + " " + ($0.displayQuantity ?? "") })
        }
        // 새벽 2:30~4:30, 10:45~11:30은 비운다(끊긴 구간)
        var readings: [GlucoseReadings.Reading] = []
        for slot in 0..<96 {
            let hour = Double(slot) / 4
            let missing = (2.5..<4.5).contains(hour) || (10.75..<11.5).contains(hour)
            let base = 130 + 45 * sin((hour - 7) / 24 * 2 * .pi) + (hour > 8 && hour < 11 ? 60 * sin((hour - 8) / 3 * .pi) : 0)
                - (hour > 14.5 && hour < 16 ? 70 * sin((hour - 14.5) / 1.5 * .pi) : 0)
            readings.append(.init(time: String(format: "%02d:%02d", slot / 4, slot % 4 * 15),
                                  value: missing ? nil : Int(base), flag: "NORMAL"))
        }
        let points = GlucosePoint.points(from: readings, on: day, calendar: ReportDay.calendar)
        let values = points.map(\.value)
        let low = values.min() ?? 0, high = values.max() ?? 0
        let coverage = Double(values.count) / 96
        let average = Double(values.reduce(0, +)) / Double(max(1, values.count))
        let report = DailyReport(
            date: ReportDay.apiString(from: day),
            glucose: .init(coverageRatio: coverage, average: average, min: low, max: high, readingsCount: values.count, sufficient: true),
            episodes: [
                .init(startAt: at(day, 8, 10), originalContext: .meal, effectiveContext: .meal, autoReclassified: false,
                      windowEndAt: at(day, 12, 10), reboundDetected: nil, intakeCount: 3,
                      foods: ["현미밥 1공기", "계란말이 1접시", "우유 1잔"],
                      intakes: [mark(0), mark(1), mark(2)]),
                .init(startAt: at(day, 11), originalContext: .snack, effectiveContext: .snack, autoReclassified: false,
                      windowEndAt: at(day, 15), reboundDetected: nil, intakeCount: 1,
                      foods: ["요거트 1개"], intakes: [mark(3)]),
                .init(startAt: at(day, 15, 30), originalContext: .hypoTreatment, effectiveContext: .hypoTreatment, autoReclassified: false,
                      windowEndAt: at(day, 17, 30), reboundDetected: false, intakeCount: 1,
                      foods: ["포도당 캔디 3개"]),
                .init(startAt: at(day, 19, 0), originalContext: .meal, effectiveContext: .meal, autoReclassified: false,
                      windowEndAt: at(day, 23, 0), reboundDetected: nil, intakeCount: 1,
                      foods: ["김치찌개 1그릇"], intakes: [mark(4)]),
            ],
            insulinEventsCount: 3,
            // 아침엔 식사 인슐린과 기저 인슐린을 함께 맞은 예시
            insulinEvents: [.init(occurredAt: at(day, 8, 0), units: 4, kind: "식사"),
                            .init(occurredAt: at(day, 8, 0), units: 14, kind: "기저"),
                            .init(occurredAt: at(day, 18, 50), units: 5, kind: "식사")],
            educationCards: [],
            summary: ["혈당 그래프 \(values.count)칸을 읽었어요.", "섭취 기록 묶음 4건, 인슐린 기록 3건이 있어요."],
            // 서버 DailyStoryBuilder처럼 시간순 문장(인슐린은 가까운 식사 장면에 함께)
            story: ["이 날 그래프에서 읽힌 값은 최저 \(low), 최고 \(high)이었어요.",
                    "새벽 2시 30분부터 오전 4시 15분까지는 그래프가 비어 있어 이 구간은 알 수 없어요.",
                    "오전 8시에 식사 4단위와 기저 14단위를 기록했고, 오전 8시 10분에 현미밥, 계란말이, 우유를 먹었어요.",
                    "오전 11시에 요거트를 먹었어요.",
                    "오후 3시 30분에 저혈당 대응으로 포도당 캔디를 먹었어요.",
                    "오후 6시 50분에 식사 5단위를 기록했고, 오후 7시에 김치찌개를 먹었어요."],
            insights: [],
            reboundGlucoseThreshold: 180)

        return (report, points)
    }

    static func insulinRecord(for marker: DailyReport.InsulinMarker) -> InsulinRecord? {
        let events = daily(marker.occurredAt).0.insulinEvents ?? []
        guard let index = events.firstIndex(where: {
            $0.occurredAt == marker.occurredAt && $0.units == marker.units && $0.kind == marker.kind
        }) else { return nil }
        return .init(id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", index + 1))!,
                     occurredAt: marker.occurredAt, units: marker.units, kind: marker.kind)
    }

    static func food(_ day: Date, weekly: Bool) -> FoodObservationReport {
        if !weekly {
            let points = daily(day).1
            let baseline = points.last { $0.time <= at(day, 8, 10) }!
            let window = points.filter { $0.time > at(day, 8, 10) && $0.time <= at(day, 12, 10) }
            let peak = window.max { $0.value < $1.value }!
            let last = window.last!
            let observation = FoodObservationReport.Observation(
                intakeId: "sample-1", occurredAt: at(day, 8, 10), context: .meal,
                foods: [.init(name: "현미밥", count: 1, unit: "공기")], windowEndAt: at(day, 12, 10), windowMinutes: 240,
                status: "LIMITED", baseline: .init(time: baseline.time, value: baseline.value),
                peak: .init(time: peak.time, value: peak.value), peakDelta: peak.value - baseline.value,
                endReading: .init(time: last.time, value: last.value), endDelta: last.value - baseline.value,
                readingsCount: window.count, expectedReadingsCount: 16, coverageRatio: Double(window.count) / 16,
                clippedReadingsCount: 0, overlappingIntakeIds: ["sample-2", "sample-3", "sample-4"],
                insulinEventsCount: 1, comparable: false, notes: ["관찰 구간에 다른 음식 기록과 끊긴 구간이 있어요."],
                summary: "기록 직전 \(baseline.value)에서 \(ReportDay.timeString(from: peak.time))에 \(peak.value)까지 읽혔어요.")
            return .init(kind: "DAILY", observations: [observation], repeatedFoods: [],
                         limitations: ["화면 확인을 위해 만든 예시 기록이에요."])
        }
        let observation = FoodObservationReport.Observation(
            intakeId: "sample-1", occurredAt: at(day, 8, 10), context: .meal,
            foods: [.init(name: "김밥", count: 1, unit: "줄")], windowEndAt: at(day, 12, 10), windowMinutes: 240,
            status: "OBSERVED", baseline: .init(time: at(day, 8, 0), value: 118), peak: .init(time: at(day, 9, 30), value: 204),
            peakDelta: 86, endReading: .init(time: at(day, 12, 0), value: 131), endDelta: 13,
            readingsCount: 16, expectedReadingsCount: 16, coverageRatio: 1, clippedReadingsCount: 0,
            overlappingIntakeIds: [], insulinEventsCount: 1, comparable: true, notes: ["관찰 구간에 인슐린 기록 1건이 있어요."],
            summary: "기록 직전 118에서 9:30에 204까지 읽혔어요.")
        return FoodObservationReport(
            kind: weekly ? "WEEKLY" : "DAILY", observations: [observation],
            repeatedFoods: weekly ? [.init(id: "g1", context: .meal, foods: [.init(name: "김밥", count: 1, unit: "줄")],
                                           recordsCount: 2, comparableCount: 2, comparisonDays: 2, insulinAccompaniedCount: 2,
                                           amountUnknown: false, meanPeakDelta: 80, minPeakDelta: 74, maxPeakDelta: 86,
                                           intakeIds: ["sample-1"], comparableIntakeIds: ["sample-1"],
                                           summary: "같은 기록 2건에서 읽힌 최고값 차이는 +74 ~ +86이었어요.")] : [],
            limitations: ["이미지에서 읽은 추정값이라 실제 측정값과 다를 수 있어요."])
    }

    /// 주간 겹쳐 보기 예시: 하루 예시 곡선을 요일마다 조금씩 다르게(금·토·일은 비움)
    static func weekOverlay(_ weekStart: Date) -> [(date: Date, points: [GlucosePoint])] {
        (0..<7).compactMap { offset -> (date: Date, points: [GlucosePoint])? in
            guard let date = ReportDay.calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            guard offset < 4 else { return (date, []) }
            let base = daily(date).1
            let shifted = base.map { GlucosePoint(time: $0.time.addingTimeInterval(Double(offset) * 1800),
                                                  value: max(50, $0.value + (offset - 1) * 12), segment: $0.segment) }
                .filter { ReportDay.calendar.isDate($0.time, inSameDayAs: date) }
            return (date, shifted)
        }
    }

    static func weekly(_ weekStart: Date) -> WeeklyReport {
        WeeklyReport(weekStart: ReportDay.apiString(from: weekStart),
                     weekEnd: ReportDay.apiString(from: ReportDay.calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart),
                     daysWithData: 5, daysInsufficient: 1, averageGlucose: 146, episodesCount: 14, reboundCount: 1,
                     insulinEventsCount: 11, sufficientDays: 4, lowCoverageDays: 1, pendingDays: 1,
                     summary: ["그래프가 있는 날은 5일이에요.", "섭취 기록 묶음 14건, 인슐린 기록 11건이 있어요."],
                     story: ["이번 주는 4일 그래프가 있었고, 읽힌 값 평균은 146이었어요.",
                             "가장 높았던 값은 수요일 오전 9시 30분의 262, 가장 낮았던 값은 월요일 오후 3시 15분의 52였어요.",
                             "시간대별로 보면 오전이 평균 168로 가장 높고, 새벽이 112로 가장 낮았어요.",
                             "가장 자주 남긴 음식은 현미밥(4번)이에요.",
                             "앞뒤 1시간 안에 인슐린 기록이 없는 식사·간식은 2번이었어요.",
                             "'먹지 않은 새벽에 혈당이 올랐어요' 흐름이 2일 보였어요(화요일·수요일)."],
                     days: (0..<7).map { offset in
                         let date = ReportDay.apiString(from: ReportDay.calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart)
                         return offset < 4
                             ? .init(date: date, average: Double(132 + offset * 12), min: 52 + offset * 10, max: 226 + offset * 12,
                                     coverageRatio: 0.92, intakeCount: 3, insulinCount: 2, lowCount: offset == 0 ? 1 : 0,
                                     insightCodes: offset == 1 || offset == 2 ? ["NIGHT_FASTING_RISE"] : [])
                             : .init(date: date, average: nil, min: nil, max: nil, coverageRatio: nil, intakeCount: 0,
                                     insulinCount: 0, lowCount: 0, insightCodes: [])
                     },
                     timeBands: [.init(label: "새벽 0~6시", startHour: 0, endHour: 6, average: 112, min: 88, max: 150, readingsCount: 90),
                                 .init(label: "오전 6~12시", startHour: 6, endHour: 12, average: 168, min: 96, max: 262, readingsCount: 92),
                                 .init(label: "오후 12~18시", startHour: 12, endHour: 18, average: 141, min: 52, max: 210, readingsCount: 88),
                                 .init(label: "저녁 18~24시", startHour: 18, endHour: 24, average: 150, min: 100, max: 238, readingsCount: 80)],
                     insights: [.init(code: "NIGHT_FASTING_RISE", title: "먹지 않은 새벽에 혈당이 올랐어요", days: 2,
                                      dates: [ReportDay.apiString(from: weekStart.addingTimeInterval(86400)),
                                              ReportDay.apiString(from: weekStart.addingTimeInterval(2 * 86400))])])
    }

    static func clinician(days: Int) -> ClinicianReport {
        let today = ReportDay.today()
        let dayList: [ClinicianReport.Day] = (0..<days).reversed().map { offset in
            let date = ReportDay.calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let status = offset == 0 ? "IN_PROGRESS" : offset % 5 == 0 ? "NO_GRAPH" : offset % 4 == 0 ? "LOW_COVERAGE" : "SUFFICIENT"
            let hasGraph = status != "NO_GRAPH" && status != "IN_PROGRESS"
            return ClinicianReport.Day(
                date: ReportDay.apiString(from: date), status: status, coverageRatio: hasGraph ? (status == "SUFFICIENT" ? 0.93 : 0.48) : nil,
                readingsCount: hasGraph ? 89 : 0, missingCount: hasGraph ? 7 : 96,
                average: hasGraph ? Double(130 + offset % 3 * 9) : nil, min: hasGraph ? 66 : nil, max: hasGraph ? 231 : nil,
                lowReadingCount: hasGraph && offset % 3 == 0 ? 1 : 0, aboveRangeCount: 0, belowRangeCount: 0,
                lowReadings: hasGraph && offset % 3 == 0 ? [.init(time: at(date, 15, 15), value: 66, flag: "NORMAL")] : [],
                episodes: [.init(startAt: at(date, 8, 10), enteredContext: .meal, effectiveContext: .meal, autoReclassified: false,
                                 windowEndAt: at(date, 12, 10), aboveReboundThresholdObserved: nil, intakeCount: 2)],
                insulinEvents: [.init(occurredAt: at(date, 8, 0), units: 4, kind: "식사")])
        }
        return ClinicianReport(
            from: dayList.first?.date ?? "", to: dayList.last?.date ?? "", generatedAt: .now,
            lowReadingThreshold: 70, reboundThreshold: 180,
            totals: .init(periodDays: days, daysSufficient: days - days / 4 - days / 5 - 1, daysLowCoverage: days / 4,
                          daysNoGraph: days / 5, daysInProgress: 1, readingsCount: 89 * (days - days / 5 - 1),
                          average: 138, min: 62, max: 245, lowReadingCount: days / 3, aboveRangeCount: 2, belowRangeCount: 0,
                          episodesCount: days, hypoTreatmentEpisodesCount: 1, insulinEventsCount: days),
            days: dayList,
            notes: ["사용자가 올린 혈당 그래프 이미지에서 읽은 추정값이에요.", "끊긴 구간은 보간하지 않았어요."],
            disclaimer: "일반 정보이며 의료 조언이 아닙니다.")
    }
}
#endif
