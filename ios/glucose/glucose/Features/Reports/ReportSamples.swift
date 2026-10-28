//
//  ReportSamples.swift
//  glucose
//
//  DEBUG 전용: 실행 인자 -reports -reportSample 이면 서버 대신 예시 값으로 리포트를 그린다(로그인 없이 화면 확인).
//  실제 사용자 데이터가 아니라 손으로 만든 값이다.
//

#if DEBUG
import Foundation

enum ReportSamples {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-reportSample") }

    private static func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
        ReportDay.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func daily(_ day: Date) -> (DailyReport, [GlucosePoint]) {
        let report = DailyReport(
            date: ReportDay.apiString(from: day),
            glucose: .init(coverageRatio: 0.92, average: 142, min: 64, max: 238, readingsCount: 88, sufficient: true),
            episodes: [
                .init(startAt: at(day, 8, 10), originalContext: .meal, effectiveContext: .meal, autoReclassified: false,
                      windowEndAt: at(day, 12, 10), reboundDetected: nil, intakeCount: 2,
                      foods: ["현미밥 1공기", "계란말이 1접시"],
                      intakes: [.init(occurredAt: at(day, 8, 10), context: .meal, photoId: nil, foods: ["현미밥 1공기"]),
                                .init(occurredAt: at(day, 8, 40), context: .meal, photoId: nil, foods: ["계란말이 1접시"])]),
                .init(startAt: at(day, 15, 30), originalContext: .snack, effectiveContext: .hypoTreatment, autoReclassified: true,
                      windowEndAt: at(day, 17, 30), reboundDetected: false, intakeCount: 1,
                      foods: ["포도당 캔디 3개"]),
                .init(startAt: at(day, 19, 0), originalContext: .meal, effectiveContext: .meal, autoReclassified: false,
                      windowEndAt: at(day, 23, 0), reboundDetected: nil, intakeCount: 3,
                      foods: ["백미밥 1공기", "김치찌개 1그릇", "계란말이 1접시"]),
            ],
            insulinEventsCount: 2,
            insulinEvents: [.init(occurredAt: at(day, 8, 0), units: 4, kind: "식사"),
                            .init(occurredAt: at(day, 18, 50), units: 5, kind: "식사")],
            educationCards: [],
            summary: ["혈당 그래프가 하루의 92% 읽혔어요.", "섭취 기록 묶음 3건, 인슐린 기록 2건이 있어요."],
            story: ["이 날 그래프에서 읽힌 값은 최저 64, 최고 238이었어요.",
                    "밤 2시 30분부터 오전 4시 30분까지는 그래프가 비어 있어 이 구간은 알 수 없어요.",
                    "오전 8시에 식사 4단위를 기록했고, 오전 8시 10분에 현미밥 1공기, 계란말이 1접시를 먹었어요.",
                    "먹기 전 120이었던 혈당은 1시간 20분 뒤 238로 가장 높았고, 오전 11시쯤 150으로 내려왔어요.",
                    "오후 3시 15분쯤 혈당이 64까지 읽혀 오후 3시 30분에 포도당 캔디 3개를 먹었어요.",
                    "그 뒤 15분 만에 88로 올라왔고, 2시간 동안 180을 넘는 값은 없었어요."],
            insights: [.init(code: "NIGHT_FASTING_RISE", title: "먹지 않은 새벽에 혈당이 올랐어요",
                             body: "밤 2시쯤 100이던 혈당이 오전 6시쯤 160까지 올랐고, 그 사이 음식 기록은 없어요. 이런 흐름은 새벽에 나오는 호르몬이 혈당을 올리는 '새벽 현상'일 가능성이 있어요. 며칠 반복되면 기록을 가지고 의료진과 확인해 보세요.",
                             sources: [.init(name: "미국당뇨병학회(ADA) · 아침 고혈당",
                                             url: "https://diabetes.org/living-with-diabetes/high-morning-blood-glucose")],
                             reviewStatus: "DRAFT")],
            reboundGlucoseThreshold: 180)

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
        return (report, GlucosePoint.points(from: readings, on: day, calendar: ReportDay.calendar))
    }

    static func food(_ day: Date, weekly: Bool) -> FoodObservationReport {
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

    static func weekly(_ weekStart: Date) -> WeeklyReport {
        WeeklyReport(weekStart: ReportDay.apiString(from: weekStart),
                     weekEnd: ReportDay.apiString(from: ReportDay.calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart),
                     daysWithData: 5, daysInsufficient: 1, averageGlucose: 146, episodesCount: 14, reboundCount: 1,
                     insulinEventsCount: 11, sufficientDays: 4, lowCoverageDays: 1, pendingDays: 1,
                     summary: ["그래프가 있는 날은 5일이에요.", "섭취 기록 묶음 14건, 인슐린 기록 11건이 있어요."])
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
