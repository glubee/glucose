import Foundation

/// 성공한 변경만 발행한다. 날짜를 옮긴 기록도 각 화면이 현재 날짜를 다시 조회한다.
@MainActor
@Observable
final class RecordChanges {
    enum Mutation: Equatable { case created, updated, deleted }

    static let shared = RecordChanges()
    private(set) var revision = 0
    private(set) var lastMutation: Mutation?

    func publish(_ mutation: Mutation) {
        lastMutation = mutation
        revision += 1
    }
}
