//
//  DailyReportViewModel.swift
//  glucose
//
//  숫자는 전부 서버가 계산한다. 앱은 받은 값을 그대로 보여주기만 한다(같은 데이터면 같은 화면).
//

import Foundation

@Observable
final class DailyReportViewModel {

    enum State {
        case loading
        case loaded(DailyReport, [GlucosePoint])
        case failed(String)
    }

    private(set) var day: Date
    private(set) var state: State = .loading
    private(set) var foodAnalysis: FoodAnalysisState = .loading
    private(set) var requiresGraphReprocessing = false
    private(set) var isReprocessing = false
    private(set) var reprocessError: String?
    private var loadID = UUID()

    init(day: Date = ReportDay.today()) {
        self.day = day
    }

    var canGoForward: Bool {
        day < ReportDay.today()
    }

    func move(byDays days: Int) async {
        guard let newDay = ReportDay.calendar.date(byAdding: .day, value: days, to: day) else { return }
        day = min(newDay, ReportDay.today())
        await load()
    }

    func show(day newDay: Date) async {
        day = ReportDay.calendar.startOfDay(for: newDay)
        await load()
    }

    func load() async {
        let activeID = UUID()
        loadID = activeID
        let requestedDay = day
        let dayString = ReportDay.apiString(from: requestedDay)
        state = .loading
        foodAnalysis = .loading
        async let foodRequest = fetchFoodAnalysis(dayString: dayString)

        do {
            let report: DailyReport = try await APIClient.shared.send(path: "/v1/reports/daily/\(dayString)")
            // 오래된 그래프는 서버 집계에서 제외된다. glucose가 nil이어도 재분석 필요 여부를 조회한다.
            let graph = await fetchPoints(dayString: dayString, day: requestedDay)
            guard requestedDay == day, loadID == activeID else { return }
            requiresGraphReprocessing = graph.requiresReprocessing
            state = .loaded(report, graph.points)
            let analysis = await foodRequest
            guard requestedDay == day, loadID == activeID else { return }
            foodAnalysis = analysis
        } catch {
            guard requestedDay == day, loadID == activeID else { return }
            state = .failed(Self.message(for: error))
        }
    }

    private func fetchFoodAnalysis(dayString: String) async -> FoodAnalysisState {
        do {
            let report: FoodObservationReport = try await APIClient.shared.send(
                path: "/v1/reports/daily/\(dayString)/food-observations")
            return .loaded(report)
        } catch { return .failed }
    }

    private func fetchPoints(dayString: String, day: Date) async -> (points: [GlucosePoint], requiresReprocessing: Bool) {
        do {
            let readings: GlucoseReadings = try await APIClient.shared.send(path: "/v1/glucose-readings/\(dayString)")
            return (GlucosePoint.points(from: readings.readings, on: day, calendar: ReportDay.calendar), false)
        } catch APIError.server(409, let body) where body.code == "GRAPH_REPROCESS_REQUIRED" {
            return ([], true)
        } catch {
            return ([], false)
        }
    }

    func reprocessGraph() async {
        guard !isReprocessing else { return }
        let requestedDay = day
        isReprocessing = true
        reprocessError = nil
        defer { isReprocessing = false }
        do {
            let response: GraphReprocessResponse = try await APIClient.shared.send(
                path: "/v1/glucose-graphs/by-date/\(ReportDay.apiString(from: requestedDay))/reprocess", method: .post)
            for _ in 0..<60 {
                try Task.checkCancellation()
                do {
                    let result: GraphStatusResponse = try await APIClient.shared.send(
                        path: "/v1/glucose-graphs/\(response.uploadId.uuidString)")
                    guard requestedDay == day else { return }
                    if let parsedDay = ReportDay.date(fromAPIString: result.date) {
                        await show(day: parsedDay)
                    } else {
                        await load()
                    }
                    return
                } catch APIError.server(409, let body) where body.code == "GRAPH_NOT_READY" {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
            guard requestedDay == day else { return }
            reprocessError = "분석이 계속 진행 중이에요. 잠시 후 새로고침해 주세요."
        } catch is CancellationError {
            return
        } catch APIError.server(_, let body) {
            guard requestedDay == day else { return }
            reprocessError = GraphUploadViewModel.failureMessage(forCode: body.code)
        } catch {
            guard requestedDay == day else { return }
            reprocessError = "그래프를 다시 읽지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    private static func message(for error: Error) -> String {
        if case APIError.network = error {
            return "네트워크 연결을 확인해주세요."
        }
        return "리포트를 불러오지 못했어요."
    }
}
