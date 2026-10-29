//
//  DailyStoryCard.swift
//  glucose
//
//  하루 이야기(서버 DailyStoryBuilder): 그날 기록과 읽힌 값을 시간순 한 문단으로 보여준다.
//  예전 요약 줄(summary)은 "근거 보기"에 둔다. 앱은 문장을 만들거나 고치지 않는다.
//

import SwiftUI

struct DailyStoryCard: View {
    let story: [String]
    let evidence: [String]
    var title = "하루 이야기"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: title)
            Text(story.joined(separator: " "))
                .font(.body1)
                .foregroundStyle(Color.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !evidence.isEmpty {
                DisclosureGroup("근거 보기") {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(evidence.indices, id: \.self) { index in
                            Text("· " + evidence[index])
                                .font(.caption1)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.xs)
                }
                .font(.caption1)
                .tint(Color.textPrimary)
            }
            Text("그래프 이미지에서 읽은 값과 남긴 기록을 시간순으로 적었어요. 수치가 바뀐 이유는 판단하지 않아요.")
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
        }
        .card(.brand)
    }
}

#Preview {
    DailyStoryCard(story: ["이 날 그래프에서 읽힌 값은 최저 95, 최고 168 mg/dL였어요.",
                           "오전 8시에 노보래피드 4단위를 기록했고, 오전 8시 10분에 현미밥 1공기를 먹었어요."],
                   evidence: ["이 날 혈당 그래프의 92%를 읽었어요."])
        .padding()
}
