import Foundation

/// 일반 실행은 기존 서버/기기 저장소, 명시적인 DEBUG 예시는 격리된 메모리 저장소를 쓴다.
@MainActor
enum RecordDataSource {
    static var isPreview: Bool {
        #if DEBUG
        TimelineSamples.isEnabled
        #else
        false
        #endif
    }
    static var repository: RecordRepository {
        #if DEBUG
        if isPreview { return TimelineSamples.shared }
        #endif
        return LiveRecordRepository()
    }
    static var intakeService: IntakeServing {
        #if DEBUG
        if isPreview { return TimelineSamples.shared }
        #endif
        return IntakeService()
    }
    static var insulinService: InsulinServing {
        #if DEBUG
        if isPreview { return TimelineSamples.shared }
        #endif
        return InsulinService()
    }
    static var photos: PendingPhotoStore {
        #if DEBUG
        if isPreview { return TimelineSamples.shared.photos }
        #endif
        return .shared
    }
    static var dayClose: DayCloseStore {
        #if DEBUG
        if isPreview { return TimelineSamples.shared.dayClose }
        #endif
        return .shared
    }
    static var preferences: UserPreferences {
        #if DEBUG
        if isPreview { return TimelineSamples.shared.preferences }
        #endif
        return .shared
    }
}
