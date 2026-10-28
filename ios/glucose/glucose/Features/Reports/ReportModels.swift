//
//  ReportModels.swift
//  glucose
//
//  docs/backend-api.md 14번(혈당 시계열), 16번(리포트) 참고.
//  날짜 필드(date, week_start 등)는 "yyyy-MM-dd" 문자열이라 String으로 받는다(ReportDay 참고).
//

import Foundation

enum FoodAnalysisState {
    case loading
    case loaded(FoodObservationReport)
    case failed
}

struct FoodObservationReport: Decodable {
    let kind: String
    let observations: [Observation]
    let repeatedFoods: [RepeatedFood]
    let limitations: [String]

    struct Food: Decodable {
        let name: String
        let count: Int?
        let unit: String?
        var displayName: String {
            guard let count, let unit, !unit.isEmpty else { return name }
            return "\(name) \(count)\(unit)"
        }
    }
    struct Reading: Decodable {
        let time: Date
        let value: Int
    }
    struct Observation: Decodable, Identifiable {
        let intakeId: String
        let occurredAt: Date
        let context: IntakeContext
        let foods: [Food]
        let windowEndAt: Date
        let windowMinutes: Int
        let status: String
        let baseline: Reading?
        let peak: Reading?
        let peakDelta: Int?
        let endReading: Reading?
        let endDelta: Int?
        let readingsCount: Int
        let expectedReadingsCount: Int
        let coverageRatio: Double
        let clippedReadingsCount: Int
        let overlappingIntakeIds: [String]
        let insulinEventsCount: Int
        let comparable: Bool
        let notes: [String]
        let summary: String
        var id: String { intakeId }
        var foodNames: String { foods.isEmpty ? "음식명 없는 섭취" : foods.map(\.displayName).joined(separator: " · ") }
    }
    struct RepeatedFood: Decodable, Identifiable {
        let id: String
        let context: IntakeContext
        let foods: [Food]
        let recordsCount: Int
        let comparableCount: Int
        let comparisonDays: Int
        let insulinAccompaniedCount: Int
        let amountUnknown: Bool
        let meanPeakDelta: Decimal?
        let minPeakDelta: Int?
        let maxPeakDelta: Int?
        let intakeIds: [String]
        let comparableIntakeIds: [String]
        let summary: String
        var foodNames: String { foods.map(\.displayName).joined(separator: " · ") }
    }
}

struct DailyReport: Decodable {
    let date: String
    /// nil이면 그날 분석된 그래프가 없다 = 판단 불가
    let glucose: GlucoseSummary?
    let episodes: [Episode]
    let insulinEventsCount: Int
    /// 서버가 아직 이 필드를 안 보내는 버전이면 nil (마커만 안 그려진다)
    let insulinEvents: [InsulinMarker]?
    let educationCards: [EducationCard]
    let summary: [String]?
    /// 하루 이야기(시간순 문장). 예전 서버는 보내지 않는다
    var story: [String]? = nil
    /// 흐름 안내(서버 DailyInsightDetector, 검토 전 문구). 서버 설정이 꺼져 있으면 비어 있다
    var insights: [Insight]? = nil
    /// 반동 판정 기준(mg/dL, 이 값을 넘으면 반동). 서버 설정값이라 앱에 숫자를 따로 두지 않는다. 옛 서버면 nil
    let reboundGlucoseThreshold: Int?

    struct GlucoseSummary: Decodable {
        let coverageRatio: Double
        let average: Double?
        let min: Int?
        let max: Int?
        let readingsCount: Int
        let sufficient: Bool?
    }

    struct Episode: Decodable, Identifiable {
        let startAt: Date
        let originalContext: IntakeContext
        let effectiveContext: IntakeContext
        /// nil = 직전 혈당 데이터가 없어 판단 불가 (false와 다르다)
        let autoReclassified: Bool?
        let windowEndAt: Date
        /// nil = 분석 구간 안에 혈당 데이터가 없어 판단 불가
        let reboundDetected: Bool?
        let intakeCount: Int
        /// 묶음 안 음식 이름(+개수·단위). 예전 서버는 보내지 않는다
        var foods: [String]? = nil
        /// 묶음 안 섭취 기록 하나하나(정확한 시각·사진). 예전 서버는 보내지 않는다
        var intakes: [IntakeMark]? = nil

        struct IntakeMark: Decodable, Identifiable, Hashable {
            let occurredAt: Date
            let context: IntakeContext
            let photoId: UUID?
            var foods: [String]? = nil

            var id: Date { occurredAt }
        }

        /// 그래프에 찍을 기록들(예전 서버면 묶음 시작 시각 하나)
        var marks: [IntakeMark] {
            if let intakes, !intakes.isEmpty { return intakes }
            return [IntakeMark(occurredAt: startAt, context: effectiveContext, photoId: nil, foods: foods)]
        }

        var id: Date { startAt }
    }

    struct InsulinMarker: Decodable {
        let occurredAt: Date
        let units: Double
        let kind: String
    }

    struct EducationCard: Decodable, Identifiable {
        let code: String?
        let trigger: String?
        let title: String
        let body: String
        let sources: [Source]?
        let reviewedBy: String?
        /// yyyy-MM-dd. 작성일이 아니라 실제 문구 검토일이다.
        let reviewedAt: String?
        let reviewType: String?

        var id: String { code ?? trigger ?? title }

        struct Source: Decodable, Identifiable {
            let name: String
            let url: String?
            let kind: String
            var id: String { name }
        }
    }
}

extension DailyReport {
    struct Insight: Decodable, Identifiable {
        let code: String
        let title: String
        let body: String
        let sources: [Source]
        let reviewStatus: String?

        var id: String { code }

        struct Source: Decodable, Hashable {
            let name: String
            let url: String?
        }
    }
}

struct WeeklyReport: Decodable {
    let weekStart: String
    let weekEnd: String
    let daysWithData: Int
    let daysInsufficient: Int
    /// 읽힌 관측값 수로 가중한 평균. 읽힌 값이 없으면 nil
    let averageGlucose: Double?
    let episodesCount: Int
    let reboundCount: Int
    let insulinEventsCount: Int
    let sufficientDays: Int?
    let lowCoverageDays: Int?
    let pendingDays: Int?
    let summary: [String]?
}

struct ReportNarrative: Decodable {
    let kind: String
    let source: String
    let paragraphs: [Paragraph]
    let facts: [Fact]
    let limitations: [String]

    struct Paragraph: Decodable {
        let text: String
        let factIds: [String]
    }

    struct Fact: Decodable, Identifiable {
        let id: String
        let value: Decimal?
        let unit: String
        let label: String

        var displayValue: String {
            guard let value else { return "확인할 수 없음" }
            return "\(NSDecimalNumber(decimal: value).stringValue) \(unit)"
        }
    }
}

struct GlucoseReadings: Decodable {
    let date: String
    let coverageRatio: Double?
    let readings: [Reading]
    let uploadId: UUID?
    let parserVersion: String?

    struct Reading: Decodable {
        /// "HH:mm", 한국 시간 기준
        let time: String
        /// nil = 끊긴 구간(보간하지 않는다)
        let value: Int?
        let flag: String
    }
}
