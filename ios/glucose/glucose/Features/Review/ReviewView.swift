//
//  ReviewView.swift
//  glucose
//
//  리뷰 탭(v5). 이번 주 기록 요약과 "알아두면 좋은 정보" 자리.
//  안내문은 서버가 주는 고정 문구(출처·검토 상태 포함)만 쓴다.
//  대응(저혈당·고혈당) 리뷰 목록은 서버 대응 리뷰 API가 생기면 붙인다(docs/ios-design-v4.md 5장 B단계).
//

import SwiftUI

struct ReviewView: View {
    private let store = DayCloseStore.shared
    @AppStorage("guidance.nextCardIndex") private var nextCardIndex = 0
    @State private var guidanceCards: [DailyReport.EducationCard] = []
    @State private var guidanceIndex = 0
    @State private var guidanceLoading = true
    @State private var guidanceError: String?

    private var weekDone: Int {
        store.weekStates(containing: .now).filter { $0 == .done || $0 == .recordOnly }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(label: "이번 주", title: "하루 완성 \(weekDone)일")
                        WeekHoneycomb(states: store.weekStates(containing: .now))
                        Text("연속 \(store.streak(endingAt: .now))일 · 꿀단지 \(store.honeypots)개")
                            .font(.body2).foregroundStyle(Color.textSecondary)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: "알아두면 좋은 정보", trailing: "고정 안내문")
                        if guidanceLoading {
                            ProgressView("안내를 불러오고 있어요")
                        } else if let guidanceError {
                            Text(guidanceError).font(.body2).foregroundStyle(Color.textSecondary)
                            Button("다시 시도") { Task { await loadGuidance() } }
                        } else if guidanceCards.isEmpty {
                            Text("등록된 안내가 아직 없어요.").font(.body2).foregroundStyle(Color.textSecondary)
                        } else {
                            GuidanceCardContent(card: guidanceCards[guidanceIndex])
                            HStack {
                                NavigationLink("모든 안내 보기") { EducationCardsView() }
                                Spacer()
                                if guidanceCards.count > 1 {
                                    Button("다음 안내") {
                                        guidanceIndex = (guidanceIndex + 1) % guidanceCards.count
                                        nextCardIndex = (guidanceIndex + 1) % guidanceCards.count
                                    }
                                }
                            }
                            .font(.caption1)
                        }
                        Text("이 정보는 진단이나 처방이 아니에요. 치료는 의료진과 정해요.")
                            .font(.caption1).foregroundStyle(Color.textSecondary)
                    }
                    .card()
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.m)
            }
            .background(Color.canvas)
            .navigationTitle("리뷰")
            .task { await loadGuidance() }
        }
    }

    @MainActor
    private func loadGuidance() async {
        guidanceLoading = true
        guidanceError = nil
        do {
            let cards: [DailyReport.EducationCard] = try await APIClient.shared.send(path: "/v1/education-cards/review")
            guard !Task.isCancelled else { return }
            guidanceCards = cards
            if !cards.isEmpty {
                guidanceIndex = max(0, nextCardIndex) % cards.count
                nextCardIndex = (guidanceIndex + 1) % cards.count
            }
        } catch {
            guard !Task.isCancelled else { return }
            guidanceError = "안내를 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
        }
        guidanceLoading = false
    }
}

#Preview {
    ReviewView()
}
