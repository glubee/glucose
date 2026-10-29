//
//  WeeklyReportViewModel.swift
//  glucose
//
//  서버와 같은 ISO 주(월~일, 한국 시간) 단위로 이동한다.
//

import Foundation

@Observable
final class WeeklyReportViewModel {

    enum State {
        case loading
        case loaded(WeeklyReport)
        case failed(String)
    }

    private(set) var weekStart: Date
    private(set) var state: State = .loading
    private(set) var foodAnalysis: FoodAnalysisState = .loading
    /// 한 주 겹쳐 보기용 요일별 곡선(월~일, 그래프가 없거나 아직 오지 않은 날은 빈 배열)
    private(set) var overlay: [(date: Date, points: [GlucosePoint])] = []
    private var loadID = UUID()

    init(containing day: Date = ReportDay.today()) {
        self.weekStart = Self.startOfWeek(containing: day)
    }

    var weekEnd: Date {
        ReportDay.calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
    }

    var canGoForward: Bool {
        weekStart < Self.startOfWeek(containing: ReportDay.today())
    }

    func move(byWeeks weeks: Int) async {
        guard let newStart = ReportDay.calendar.date(byAdding: .weekOfYear, value: weeks, to: weekStart) else { return }
        weekStart = min(newStart, Self.startOfWeek(containing: ReportDay.today()))
        await load()
    }

    func load() async {
        let activeID = UUID()
        loadID = activeID
        let requestedWeek = weekStart
        #if DEBUG
        if ReportSamples.isEnabled {
            state = .loaded(ReportSamples.weekly(requestedWeek))
            foodAnalysis = .loaded(ReportSamples.food(requestedWeek, weekly: true))
            overlay = ReportSamples.weekOverlay(requestedWeek)
            return
        }
        #endif
        state = .loading
        foodAnalysis = .loading
        async let foodRequest = fetchFoodAnalysis(week: requestedWeek)
        async let overlayRequest = fetchOverlay(week: requestedWeek)
        do {
            let report: WeeklyReport = try await APIClient.shared.send(
                path: "/v1/reports/weekly/\(ReportDay.apiString(from: requestedWeek))"
            )
            guard requestedWeek == weekStart, loadID == activeID else { return }
            state = .loaded(report)
            let analysis = await foodRequest
            guard requestedWeek == weekStart, loadID == activeID else { return }
            foodAnalysis = analysis
            let curves = await overlayRequest
            guard requestedWeek == weekStart, loadID == activeID else { return }
            overlay = curves
        } catch {
            guard requestedWeek == weekStart, loadID == activeID else { return }
            if case APIError.network = error {
                state = .failed("네트워크 연결을 확인해주세요.")
            } else {
                state = .failed("주간 리포트를 불러오지 못했어요.")
            }
        }
    }

    /// 7일 그래프를 한꺼번에 불러온다(없는 날·실패한 날은 빈 배열)
    private func fetchOverlay(week: Date) async -> [(date: Date, points: [GlucosePoint])] {
        let calendar = ReportDay.calendar
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week) }
        let today = ReportDay.today()
        return await withTaskGroup(of: (Int, [GlucosePoint]).self) { group in
            for (index, date) in dates.enumerated() where date <= today {
                group.addTask {
                    let readings: GlucoseReadings? = try? await APIClient.shared.send(
                        path: "/v1/glucose-readings/\(ReportDay.apiString(from: date))")
                    return (index, readings.map { GlucosePoint.points(from: $0.readings, on: date, calendar: calendar) } ?? [])
                }
            }
            var byIndex: [Int: [GlucosePoint]] = [:]
            for await (index, points) in group { byIndex[index] = points }
            return dates.enumerated().map { ($0.element, byIndex[$0.offset] ?? []) }
        }
    }

    private func fetchFoodAnalysis(week: Date) async -> FoodAnalysisState {
        do {
            let report: FoodObservationReport = try await APIClient.shared.send(
                path: "/v1/reports/weekly/\(ReportDay.apiString(from: week))/food-observations")
            return .loaded(report)
        } catch { return .failed }
    }

    private static func startOfWeek(containing day: Date) -> Date {
        ReportDay.calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? ReportDay.calendar.startOfDay(for: day)
    }
}
