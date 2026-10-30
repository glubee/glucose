import XCTest
@testable import glucose

@MainActor
final class DayCloseStoreTests: XCTestCase {
    private func makeStore() -> DayCloseStore {
        DayCloseStore(defaults: UserDefaults(suiteName: "day-close-test-\(UUID())")!)
    }

    private func day(_ value: String) -> Date { ReportDay.date(fromAPIString: value)! }

    func testClosingSameDayAgainDoesNotGiveAnotherHoneypot() {
        let store = makeStore()
        for offset in 0..<7 {
            store.markClosed(ReportDay.calendar.date(byAdding: .day, value: offset, to: day("2026-10-23"))!)
        }
        XCTAssertEqual(store.streak(endingAt: day("2026-10-29")), 7)
        XCTAssertEqual(store.honeypots, 1)
        // 데모 재현처럼 같은 날을 다시 마무리
        store.markClosed(day("2026-10-29"))
        XCTAssertEqual(store.honeypots, 1)
        XCTAssertEqual(store.streak(endingAt: day("2026-10-29")), 7)
    }

    func testOnlyDemoDayCanBeReplayed() {
        XCTAssertTrue(DayCloseViewModel.isDemoReplay(day("2026-10-29")))
        XCTAssertFalse(DayCloseViewModel.isDemoReplay(day("2026-10-28")))
    }
}
