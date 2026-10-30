//
//  DayCloseViewModel.swift
//  glucose
//
//  하루 마무리 "글루비와 쓰는 줄노트"(디자이너 시안 01~09): 시작 → 한 장짜리 다이어리(그래프 · 음식 시간줄 ·
//  빠진 음식 · 투여 기록 · 한마디) → 완성.
//  완성 = 그래프 분석이 끝났거나 "기록만 저장"을 고름 + 확인 대기 사진 없음 + 빠진 음식·투여 질문에 답함.
//

import Foundation

@MainActor
@Observable
final class DayCloseViewModel {

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
    /// 시작 화면(01)을 지나 다이어리를 펼쳤는지
    var started = false
    /// "이 밖에 드신 것도 있나요?"에 답함(이게 전부예요)
    var foodsAnswered = false
    /// "기록하지 않은 투여가 있었나요?"에 답함(없어요 · 기록함)
    var insulinAnswered = false
    /// 데모 재현(DEBUG, 10/29): 서버에 그래프가 있어도 이 화면에선 처음처럼 "붙이기"부터 보여준다.
    /// 서버 그래프는 지우지 않는다. 같은 날 스크린샷을 다시 올리면(덮어쓰기) 붙은 것으로 본다
    private var replayGraphPending = false
    /// 오늘에 남길 한마디(선택, 기기에만 저장)
    var note: String {
        didSet { dayCloseStore.setNote(note, for: day) }
    }
    let graphUploader = GraphUploadViewModel()
    let report: DailyReportViewModel
    /// 그래프가 짧아 "기록만 저장"을 골랐는지
    private(set) var recordOnly = false
    private(set) var isFinished = false
    /// 완성 연출용: 이번 마무리 전 연속일
    private(set) var streakBefore = 0

    let photoStore: PendingPhotoStore
    private let dayCloseStore: DayCloseStore

    init(day: Date? = nil, photoStore: PendingPhotoStore = .shared, dayCloseStore: DayCloseStore = .shared) {
        let target = day ?? dayCloseStore.targetDay()
        self.day = target
        self.report = DailyReportViewModel(day: target)
        self.photoStore = photoStore
        self.dayCloseStore = dayCloseStore
        self.note = dayCloseStore.note(for: target)
        replayGraphPending = Self.isDemoReplay(target)
        if dayCloseStore.isClosed(target) && !Self.isDemoReplay(target) {
            isFinished = true
            started = true
        }
        #if DEBUG
        // 시뮬레이터 확인용: 실행 인자 -dayCloseStep <0~3>
        // 0 시작 화면, 1 다이어리(그래프 없이 "기록만 저장"), 2 빠진 음식까지 답함, 3 완성
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-dayCloseStep"), index + 1 < arguments.count,
           let raw = Int(arguments[index + 1]) {
            recordOnly = raw >= 1
            started = raw >= 1
            foodsAnswered = raw >= 2
            if raw >= 3 { isFinished = true; streakBefore = 12 }
        }
        #endif
    }

    var dayTitle: String { ReportDay.displayString(from: day) }

    /// 데모 영상용(DEBUG): 이미 마무리한 날이라도 처음부터 다시 진행하는 날. 실제 사용자 하루 2026-10-29
    static let demoReplayDays: Set<String> = ["2026-10-29"]

    static func isDemoReplay(_ day: Date) -> Bool {
        #if DEBUG
        return demoReplayDays.contains(ReportDay.apiString(from: day))
        #else
        return false
        #endif
    }

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
        if replayGraphPending {
            if case .done(let date, _) = graphUploader.state, date != ReportDay.apiString(from: day) {
                return .otherDay(ReportDay.displayString(fromAPIString: date))
            }
            return .needsUpload
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
        if case .done(let date, _) = graphUploader.state {
            if date == ReportDay.apiString(from: day) { replayGraphPending = false }
            await refresh()
        }
    }

    func chooseAnotherScreenshot() {
        graphUploader.reset()
    }

    /// 그래프가 짧은 날: 기록만 저장하고 다음 단계로(완성으로 친다)
    func saveRecordsOnly() {
        recordOnly = true
        graphUploader.reset()
    }

    // MARK: - 사진

    /// 이날 찍었지만 아직 확인하지 않은 사진(찍은 순서)
    var pendingPhotos: [PendingPhoto] {
        photoStore.photos
            .filter { !$0.hasConfirmedRecord && ReportDay.calendar.isDate($0.capturedAt, inSameDayAs: day) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    var isUploadingPhotos: Bool { photoStore.isUploading }

    func confirmed(_ photo: PendingPhoto) async {
        photoStore.finishConfirmation(photo.id)
        await refresh()
    }

    func discard(_ photo: PendingPhoto) {
        photoStore.remove(photo.id)
    }

    func retryUploads() async {
        await photoStore.uploadPending()
    }

    // MARK: - 진행

    var hasGraphOrRecordOnly: Bool { isGraphReady || recordOnly }

    /// 위 진행 막대(0~1)
    var progress: Double {
        if isFinished { return 1 }
        var value = 0.08
        if hasGraphOrRecordOnly { value += 0.27 }
        if hasGraphOrRecordOnly && pendingPhotos.isEmpty { value += 0.2 }
        if foodsAnswered { value += 0.2 }
        if insulinAnswered { value += 0.2 }
        return min(value, 0.95)
    }

    /// 진행 막대 오른쪽 초록 글씨: 지금 살펴볼 곳
    var progressLabel: String {
        if isFinished { return "오늘 돌아보기 완료" }
        if !started { return "식사 돌아보기" }
        if !hasGraphOrRecordOnly { return "그래프 붙이기" }
        if !pendingPhotos.isEmpty { return "사진 확인하기" }
        if !foodsAnswered { return "빠진 기록 살펴보기" }
        if !insulinAnswered { return "투여 기록 살펴보기" }
        return "오늘의 마지막"
    }

    var canFinish: Bool {
        hasGraphOrRecordOnly && pendingPhotos.isEmpty && foodsAnswered && insulinAnswered && !isFinished
    }

    func finish() async {
        guard canFinish else { return }
        // 이미 마무리한 날을 다시 하는 경우(데모 재현) 연출은 이 날을 빼고 센 연속에서 시작한다
        let streak = dayCloseStore.streak(endingAt: day)
        streakBefore = dayCloseStore.isClosed(day) ? max(0, streak - 1) : streak
        dayCloseStore.markClosed(day, recordOnly: recordOnly)
        isFinished = true
        WidgetSnapshot.refresh()
        // 마무리한 날의 알림은 빼고 다시 예약한다
        await NudgeScheduler.refresh()
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
