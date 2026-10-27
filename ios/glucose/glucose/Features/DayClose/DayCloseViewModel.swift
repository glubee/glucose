//
//  DayCloseViewModel.swift
//  glucose
//
//  하루 마무리: 리브레 그래프 → 낮에 찍은 사진 확인 → 빠진 기록 추가 → 완성 (docs/ios-design-v4.md 0장).
//  완성 = 그날 그래프 분석이 끝났고, 확인 대기 사진이 남지 않은 상태에서 "오늘 정리 마치기".
//

import Foundation

@MainActor
@Observable
final class DayCloseViewModel {

    enum GraphStatus: Equatable {
        case checking
        case missing
        /// 읽힌 비율(0~1)
        case ready(coverage: Double)
        case failed(String)
    }

    let day: Date
    private(set) var graph: GraphStatus = .checking
    private(set) var isFinished = false

    private let photoStore: PendingPhotoStore
    private let dayCloseStore: DayCloseStore

    init(day: Date? = nil, photoStore: PendingPhotoStore = .shared, dayCloseStore: DayCloseStore = .shared) {
        self.day = day ?? dayCloseStore.targetDay()
        self.photoStore = photoStore
        self.dayCloseStore = dayCloseStore
        isFinished = dayCloseStore.isClosed(self.day)
    }

    var dayTitle: String { ReportDay.displayString(from: day) }

    /// 이날 찍었지만 아직 확인하지 않은 사진(찍은 순서)
    var pendingPhotos: [PendingPhoto] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ReportDay.timeZone
        return photoStore.photos
            .filter { calendar.isDate($0.capturedAt, inSameDayAs: day) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    var isGraphReady: Bool {
        if case .ready = graph { return true }
        return false
    }

    var canFinish: Bool { isGraphReady && pendingPhotos.isEmpty && !isFinished }

    /// 마치기 버튼 아래에 보여줄, 남은 일
    var remainingHint: String? {
        if isFinished { return nil }
        var left: [String] = []
        if !isGraphReady { left.append("그래프") }
        if !pendingPhotos.isEmpty { left.append("사진 \(pendingPhotos.count)장 확인") }
        return left.isEmpty ? nil : "남은 일: " + left.joined(separator: ", ")
    }

    /// 글루비가 지금 하는 말
    var beeLine: String {
        if isFinished { return "오늘의 한 칸을 남겼어요." }
        if !isGraphReady { return "리브레 그래프부터 올려볼까요?" }
        if !pendingPhotos.isEmpty { return "낮에 찍은 사진을 같이 확인해요." }
        return "빠진 기록이 없으면 마무리해요."
    }

    func refreshGraph() async {
        do {
            let report: DailyReport = try await APIClient.shared.send(
                path: "/v1/reports/daily/\(ReportDay.apiString(from: day))"
            )
            if let glucose = report.glucose {
                graph = .ready(coverage: glucose.coverageRatio)
            } else {
                graph = .missing
            }
        } catch {
            graph = .failed("화면을 아래로 당겨 다시 시도해주세요.")
        }
    }

    func confirmed(_ photo: PendingPhoto) {
        photoStore.remove(photo.id)
    }

    func discard(_ photo: PendingPhoto) {
        photoStore.remove(photo.id)
    }

    var isUploading: Bool { photoStore.isUploading }

    func retryUploads() async {
        await photoStore.uploadPending()
    }

    func finish() async {
        guard canFinish else { return }
        dayCloseStore.markClosed(day)
        isFinished = true
        // 마무리한 날의 알림은 빼고 다시 예약한다
        await DayCloseReminder.refresh()
    }
}
