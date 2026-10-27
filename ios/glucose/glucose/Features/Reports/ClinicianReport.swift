//
//  ClinicianReport.swift
//  glucose
//
//  의료인 공유용 리포트(docs/backend-api.md `GET /v1/reports/clinician`). 사실과 데이터의 한계만 담는다.
//  숫자는 전부 서버가 계산하고 앱은 그대로 옮긴다. 진단·평가·조언 문구는 앱에서도 덧붙이지 않는다.
//

import Foundation

struct ClinicianReport: Decodable {
    let from: String
    let to: String
    let generatedAt: Date
    let lowReadingThreshold: Int
    let reboundThreshold: Int
    let totals: Totals
    let days: [Day]
    let notes: [String]
    let disclaimer: String

    struct Totals: Decodable {
        let periodDays: Int
        let daysSufficient: Int
        let daysLowCoverage: Int
        let daysNoGraph: Int
        let daysInProgress: Int
        let readingsCount: Int
        /// 읽힌 값이 없으면 nil (0이 아니다)
        let average: Double?
        let min: Int?
        let max: Int?
        let lowReadingCount: Int
        let aboveRangeCount: Int
        let belowRangeCount: Int
        let episodesCount: Int
        let hypoTreatmentEpisodesCount: Int
        let insulinEventsCount: Int
    }

    struct Day: Decodable, Identifiable {
        let date: String
        /// SUFFICIENT | LOW_COVERAGE | NO_GRAPH | IN_PROGRESS
        let status: String
        let coverageRatio: Double?
        let readingsCount: Int
        let missingCount: Int
        let average: Double?
        let min: Int?
        let max: Int?
        let lowReadingCount: Int
        let aboveRangeCount: Int
        let belowRangeCount: Int
        let lowReadings: [LowReading]
        let episodes: [Episode]
        let insulinEvents: [DailyReport.InsulinMarker]

        var id: String { date }

        var statusTitle: String {
            switch status {
            case "SUFFICIENT": "충분히 읽힘"
            case "LOW_COVERAGE": "일부만 읽힘"
            case "NO_GRAPH": "그래프 없음"
            default: "집계 중"
            }
        }
    }

    struct LowReading: Decodable {
        let time: Date
        let value: Int
        let flag: String
    }

    struct Episode: Decodable {
        let startAt: Date
        let enteredContext: IntakeContext
        let effectiveContext: IntakeContext
        /// nil = 직전 값이 없어 판단 불가
        let autoReclassified: Bool?
        let windowEndAt: Date
        /// nil = 관찰 구간에 읽힌 값이 없어 확인 불가
        let aboveReboundThresholdObserved: Bool?
        let intakeCount: Int
    }
}

@Observable
final class ClinicianReportViewModel {
    enum Period: Int, CaseIterable, Hashable {
        case week = 7, twoWeeks = 14, month = 30

        var title: String { "최근 \(rawValue)일" }
    }

    enum State {
        case loading
        case loaded(ClinicianReport)
        case failed(String)
    }

    var period: Period = .twoWeeks
    private(set) var state: State = .loading
    private var loadID = UUID()

    func load() async {
        let activeID = UUID()
        loadID = activeID
        let to = ReportDay.today()
        let from = ReportDay.calendar.date(byAdding: .day, value: -(period.rawValue - 1), to: to) ?? to
        #if DEBUG
        if ReportSamples.isEnabled {
            state = .loaded(ReportSamples.clinician(days: period.rawValue))
            return
        }
        #endif
        state = .loading
        do {
            let report: ClinicianReport = try await APIClient.shared.send(
                path: "/v1/reports/clinician",
                queryItems: [URLQueryItem(name: "from", value: ReportDay.apiString(from: from)),
                             URLQueryItem(name: "to", value: ReportDay.apiString(from: to))])
            guard loadID == activeID else { return }
            state = .loaded(report)
        } catch {
            guard loadID == activeID else { return }
            if case APIError.network = error {
                state = .failed("네트워크 연결을 확인해주세요.")
            } else {
                state = .failed("진료용 리포트를 만들지 못했어요.")
            }
        }
    }
}
