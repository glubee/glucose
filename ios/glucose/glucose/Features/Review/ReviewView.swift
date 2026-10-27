//
//  ReviewView.swift
//  glucose
//
//  리뷰 탭(v5). 이번 주 기록 요약과 "알아두면 좋은 정보" 자리.
//  안내문은 서버가 주는 고정 문구(출처·검토 상태 포함)만 쓴다. 아직 서버 API가 없어 준비 중으로 보여준다.
//  대응(저혈당·고혈당) 리뷰 목록은 서버 대응 리뷰 API가 생기면 붙인다(docs/ios-design-v4.md 5장 B단계).
//

import SwiftUI

struct ReviewView: View {
    private let store = DayCloseStore.shared

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
                        StateView(kind: .empty, title: "준비 중이에요",
                                  message: "의료인 검토를 거친 안내문이 준비되면\n출처와 함께 여기에 보여드릴게요.")
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
        }
    }
}

#Preview {
    ReviewView()
}
