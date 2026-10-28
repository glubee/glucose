//
//  DailyInsightsCard.swift
//  glucose
//
//  흐름 안내(서버 DailyInsightDetector): 그래프 모양과 기록으로 찾은 흐름에 미리 써 둔 일반 안내를 붙인 것.
//  진단이 아니라 "~일 가능성이 알려져 있어요" 수준이고, 출처를 함께 보여준다. 의료인 검토 전이면 표시한다.
//

import SwiftUI

struct DailyInsightsCard: View {
    let insights: [DailyReport.Insight]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "이렇게 볼 수 있어요",
                          trailing: insights.contains { $0.reviewStatus == "DRAFT" } ? "검토 전 안내" : nil)
            ForEach(insights) { insight in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label(insight.title, systemImage: "lightbulb")
                        .font(.headline2)
                        .foregroundStyle(Color.textPrimary)
                    Text(insight.body)
                        .font(.body2)
                        .foregroundStyle(Color.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(insight.sources, id: \.self) { source in
                        if let value = source.url, let url = URL(string: value), url.scheme == "https" {
                            Link(destination: url) {
                                Label(source.name, systemImage: "arrow.up.right.square").font(.caption1)
                            }
                            .tint(Color.textSecondary)
                        } else {
                            Text(source.name).font(.caption1).foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .padding(Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.field))
            }
            Text("일반적인 정보예요. 진단이나 처방이 아니고, 치료는 의료진과 정해요.")
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
        }
        .card()
    }
}
