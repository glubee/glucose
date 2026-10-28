//
//  ReportParts.swift
//  glucose
//
//  리포트 화면(v5) 공통 조각: 날짜 이동 줄, 큰 숫자, 데이터 칩, 작은 수치 칸, 글루비 한마디.
//  숫자는 서버 값을 그대로 쓰고, 일반 목표와 비교하는 문구는 넣지 않는다.
//

import SwiftUI

/// ‹ 10월 27일 › — 이전/다음
struct ReportPeriodNavigator: View {
    let title: String
    let previousLabel: String
    let nextLabel: String
    let canGoForward: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            arrow("chevron.left", label: previousLabel, action: onPrevious)
            Spacer()
            Text(title)
                .font(.headline2)
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
            Spacer()
            arrow("chevron.right", label: nextLabel, action: onNext)
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.3)
        }
    }

    private func arrow(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 36, height: 36)
                .background(Color.surfaceMuted, in: Circle())
                .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
        }
        .accessibilityLabel(label)
    }
}

/// 큰 숫자 + 단위. 값이 없으면 "–"
struct ReportBigNumber: View {
    let value: String?
    var unit = "mg/dL"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
            Text(value ?? "–")
                .font(.bigNumber)
                .tracking(-2)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
            Text(unit)
                .font(.pretendard(17, relativeTo: .headline, weight: .bold))
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 데이터가 얼마나 읽혔는지. 민트 = 충분, 연노랑 = 일부, 회색 = 없음·집계 중
struct ReportDataChip: View {
    enum Tone { case sufficient, limited, none }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.pretendard(13, relativeTo: .footnote, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
            .fixedSize()
    }

    private var foreground: Color {
        switch tone {
        case .sufficient: .mintStrong
        case .limited: .onBrandSoft
        case .none: .textSecondary
        }
    }

    private var background: Color {
        switch tone {
        case .sufficient: .mintSoft
        case .limited: .brandSoft
        case .none: .surfaceMuted
        }
    }
}

/// 회색 면 위 작은 수치 칸(최저·최고, 기록 건수)
struct ReportStatTile: View {
    let title: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.pretendard(22, relativeTo: .title2, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.caption1)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 10)
        .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.field))
        .accessibilityElement(children: .combine)
    }
}

/// 카드 안 회색 보조 문장 여러 줄
struct ReportNotes: View {
    let lines: [String]

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(lines.indices, id: \.self) { index in
                    Text(lines[index])
                        .font(.caption1)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// 맨 아래 작은 글루비 + 한마디. 글루비는 기록한 날만 센다(혈당 값에는 반응하지 않는다)
struct ReportBeeNote: View {
    let title: String
    var message = "글루비는 기록한 날만 세요."

    var body: some View {
        HStack(spacing: Spacing.s) {
            MascotView(pose: .nod, size: 52, motion: .none)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.pretendard(15, relativeTo: .subheadline, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(message)
                    .font(.caption1)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 불러오는 중·실패
struct ReportLoadState: View {
    let message: String?
    let onRetry: () -> Void

    var body: some View {
        if let message {
            StateView(kind: .error, title: message, actionTitle: "다시 시도", action: onRetry)
                .card()
        } else {
            StateView(kind: .loading, title: "리포트를 정리하고 있어요")
                .frame(minHeight: 240)
        }
    }
}

enum ReportFormat {
    static func glucose(_ value: Double?) -> String? {
        value.map { String(format: "%.0f", $0) }
    }

    static func percent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }
}
