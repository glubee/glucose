//
//  DayCloseViewModel.swift
//  glucose
//
//  하루 마무리(v5): 그래프 → 사진 확인 → 인슐린 → 완성 (docs/ios-design-v4.md 0장, 디자이너 v5 "하루 마무리 보강").
//  완성 = 그날 그래프 분석이 끝났거나 "기록만 저장"을 고른 상태 + 확인 대기 사진이 없음.
//

import Foundation

@MainActor
@Observable
final class DayCloseViewModel {

    enum Step: Int, CaseIterable {
        case graph, photos, insulin, done

        var title: String {
            switch self {
            case .graph: "그래프"
            case .photos: "사진 확인"
            case .insulin: "인슐린"
            case .done: "완성"
            }
        }
    }

    enum GraphPhase: Equatable {
        case checking
        case needsUpload
        case uploading
        case analyzing
        /// 읽힌 비율(0~1)
        case ready(coverage: Double)
        case notRecognized
        case tooLittle
        /// 올린 그래프의 날짜가 마무리하는 날과 다름
        case otherDay(String)
        case failed(String)
    }

    let day: Date
    private(set) var step: Step = .graph
    let graphUploader = GraphUploadViewModel()
    let report: DailyReportViewModel
    /// 그래프가 짧아 "기록만 저장"을 골랐는지
    private(set) var recordOnly = false
    private(set) var isFinished = false
    /// 완성 연출용: 이번 마무리 전 연속일
    private(set) var streakBefore = 0

    private let photoStore: PendingPhotoStore
    private let dayCloseStore: DayCloseStore

    init(day: Date? = nil, photoStore: PendingPhotoStore = .shared, dayCloseStore: DayCloseStore = .shared) {
        let target = day ?? dayCloseStore.targetDay()
        self.day = target
        self.report = DailyReportViewModel(day: target)
        self.photoStore = photoStore
        self.dayCloseStore = dayCloseStore
        if dayCloseStore.isClosed(target) {
            isFinished = true
            step = .done
        }
        #if DEBUG
        // 시뮬레이터 확인용: 실행 인자 -dayCloseStep <0~3> (그래프 없이 "기록만 저장"한 것으로 본다)
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-dayCloseStep"), index + 1 < arguments.count,
           let raw = Int(arguments[index + 1]), let debugStep = Step(rawValue: raw) {
            recordOnly = true
            step = debugStep
            if debugStep == .done { isFinished = true; streakBefore = 12 }
        }
        #endif
    }

    var dayTitle: String { ReportDay.displayString(from: day) }

    // MARK: - 그래프

    var graphPhase: GraphPhase {
        switch graphUploader.state {
        case .uploading: return .uploading
        case .analyzing: return .analyzing
        case .failed(let message):
            switch graphUploader.failureCode {
            case "GRAPH_NOT_RECOGNIZED": return .notRecognized
            case "GRAPH_TOO_LITTLE_DATA": return .tooLittle
            default: return .failed(message)
            }
        case .idle, .done:
            break
        }
        switch report.state {
        case .loading:
            return .checking
        case .failed(let message):
            return .failed(message)
        case .loaded(let dailyReport, _):
            if let glucose = dailyReport.glucose { return .ready(coverage: glucose.coverageRatio) }
            if case .done(let date, _) = graphUploader.state, date != ReportDay.apiString(from: day) {
                return .otherDay(ReportDay.displayString(fromAPIString: date))
            }
            return .needsUpload
        }
    }

    var isGraphReady: Bool {
        if case .ready = graphPhase { return true }
        return false
    }

    func refresh() async {
        await report.load()
    }

    func uploadGraph(data: Data, contentType: String) {
        graphUploader.start(imageData: data, contentType: contentType)
    }

    /// 분석이 끝나면 그날 리포트를 다시 읽어 그래프가 들어왔는지 본다
    func graphUploadChanged() async {
        if case .done = graphUploader.state { await refresh() }
    }

    func chooseAnotherScreenshot() {
        graphUploader.reset()
    }

    /// 그래프가 짧은 날: 기록만 저장하고 다음 단계로(완성으로 친다)
    func saveRecordsOnly() {
        recordOnly = true
        graphUploader.reset()
        step = .photos
    }

    // MARK: - 사진

    /// 이날 찍었지만 아직 확인하지 않은 사진(찍은 순서)
    var pendingPhotos: [PendingPhoto] {
        photoStore.photos
            .filter { ReportDay.calendar.isDate($0.capturedAt, inSameDayAs: day) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    var isUploadingPhotos: Bool { photoStore.isUploading }

    func confirmed(_ photo: PendingPhoto) async {
        photoStore.remove(photo.id)
        await refresh()
    }

    func discard(_ photo: PendingPhoto) {
        photoStore.remove(photo.id)
    }

    func retryUploads() async {
        await photoStore.uploadPending()
    }

    // MARK: - 단계 이동

    func goToPhotos() { step = .photos }
    func goToInsulin() { step = .insulin }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1), !isFinished else { return }
        step = previous
    }

    var canFinish: Bool { (isGraphReady || recordOnly) && pendingPhotos.isEmpty && !isFinished }

    func finish() async {
        guard canFinish else { return }
        streakBefore = dayCloseStore.streak(endingAt: day)
        dayCloseStore.markClosed(day, recordOnly: recordOnly)
        isFinished = true
        step = .done
        // 마무리한 날의 알림은 빼고 다시 예약한다
        await DayCloseReminder.refresh()
    }

    var streakAfter: Int { dayCloseStore.streak(endingAt: day) }

    /// 이번 주(월~일) 벌집 상태. 마무리하는 날은 연출 전까지 .today
    func weekStates(fillingToday: Bool) -> [HoneyCellState] {
        var states = dayCloseStore.weekStates(containing: day, today: day)
        if fillingToday {
            let index = (ReportDay.calendar.component(.weekday, from: day) + 5) % 7
            states[index] = .today
        }
        return states
    }
}
