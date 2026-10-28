//
//  Containers.swift
//  glucose
//
//  카드, 섹션 머리말, 시트 머리말. 스타일 원칙: 테두리·그림자는 최소, 구분은 여백으로.
//

import SwiftUI

enum CardTone {
    /// 흰 바탕 + 얇은 선
    case plain
    /// 연노랑. 합계·선택된 카드
    case brand
    /// 민트. 글루비 안내, 범위 정보
    case mint
    /// 연보라. 인슐린 기록
    case insulin

    var fill: Color {
        switch self {
        case .plain: .canvas
        case .brand: .brandSoft
        case .mint: .mintSoft
        case .insulin: .insulinSoft
        }
    }
}

extension View {
    func card(_ tone: CardTone = .plain, padding: CGFloat = Spacing.m) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.fill, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay {
                if tone == .plain {
                    RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.line, lineWidth: 1)
                }
            }
    }
}

/// "이번 주 기록   3건" 처럼 작은 라벨(선택) + 제목 + 오른쪽 보조 글
struct SectionHeader: View {
    var label: String? = nil
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            if let label {
                Text(label.uppercased())
                    .font(.sectionLabel)
                    .foregroundStyle(Color.textSecondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline2)
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: Spacing.xs)
                if let trailing {
                    Text(trailing)
                        .font(.caption1)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 시트 맨 위: 제목, 설명, 닫기(X)
struct SheetHeader: View {
    let title: String
    var subtitle: String? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.headline1)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.body2)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: Spacing.s)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Color.surfaceMuted, in: Circle())
                        .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                }
                .accessibilityLabel("닫기")
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: Spacing.m) {
            SheetHeader(title: "음식 기록", subtitle: "지난 식사도 기록할 수 있어요.", onClose: {})
            SectionHeader(label: "이번 주", title: "최근 기록한 음식", subtitle: "음식을 선택해 양을 확인하세요.", trailing: "3개")
            Text("사과 · 2조각").card()
            Text("식사 전체 · 2가지 음식").card(.brand)
            Text("범위 70–180 mg/dL").card(.mint)
            Text("인슐린 투여 · 2U").card(.insulin)
        }
        .padding(Spacing.gutter)
    }
}
