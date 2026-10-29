//
//  DailyStoryCard.swift
//  glucose
//
//  서버가 보낸 이야기의 문장 경계를 유지하고, 숫자와 시각만 시각적으로 강조한다.
//  앱은 문장·수치를 만들거나 고치지 않는다. 근거와 안내는 접어서 확인한다.
//

import SwiftUI

struct DailyStoryCard: View {
    let story: [String]
    let evidence: [String]
    var title = "하루 이야기"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: title)
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(story.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: Spacing.xs) {
                        bullet(for: story[index])
                        Text(highlighted(story[index]))
                            .font(.body1)
                            .foregroundStyle(Color.textPrimary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(evidence.indices, id: \.self) { index in
                        Text("· " + evidence[index])
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("그래프 이미지에서 읽은 값과 남긴 기록을 시간순으로 적었어요. 수치가 바뀐 이유는 판단하지 않아요.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Spacing.xs)
            } label: {
                Text(evidence.isEmpty ? "안내" : "근거 및 안내")
                    .font(.caption1.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .tint(Color.textSecondary)
        }
        .card(.brand)
    }

    /// 인슐린 기록이 들어간 문장은 주사기 표시로 구분한다(문장은 서버 그대로)
    @ViewBuilder
    private func bullet(for sentence: String) -> some View {
        if sentence.contains("단위를 기록") {
            Image(systemName: "syringe.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.insulin)
                .frame(width: 14)
                .padding(.top, 5)
                .accessibilityLabel("인슐린")
        } else {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(Color.onBrandSoft)
                .frame(width: 14)
                .padding(.top, 9)
                .accessibilityHidden(true)
        }
    }

    private func highlighted(_ source: String) -> AttributedString {
        var result = AttributedString(source)
        guard let numbers = try? NSRegularExpression(pattern: #"\d+(?:[.:]\d+)*"#) else { return result }
        for match in numbers.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let textRange = Range(match.range, in: source),
                  let range = Range(textRange, in: result) else { continue }
            result[range].font = .pretendard(16, relativeTo: .body, weight: .bold)
        }
        return result
    }
}

#Preview {
    DailyStoryCard(story: ["이 날 그래프에서 읽힌 값은 최저 95, 최고 168 mg/dL였어요.",
                           "오전 8시에 노보래피드 4단위를 기록했고, 오전 8시 10분에 현미밥 1공기를 먹었어요."],
                   evidence: ["이 날 혈당 그래프의 92%를 읽었어요."])
        .padding()
}
