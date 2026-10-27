//
//  StateView.swift
//  glucose
//
//  빈 화면·오류·불러오는 중. 오류와 빈 상태에는 웃는 글루비를 쓰지 않는다(v4 원칙).
//

import SwiftUI

struct StateView: View {
    enum Kind {
        case loading
        case empty
        case error
    }

    let kind: Kind
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.s) {
            switch kind {
            case .loading:
                ProgressView().controlSize(.large).tint(Color.textSecondary)
            case .empty:
                MascotView(pose: .magnifier, size: 88)
            case .error:
                MascotView(pose: .sulky, size: 88)
            }

            Text(title)
                .font(.headline2)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glubeeSecondary)
                    .frame(maxWidth: 240)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack(spacing: Spacing.l) {
        StateView(kind: .loading, title: "음식을 확인하고 있어요")
        StateView(kind: .empty, title: "음식을 찾지 못했어요.", message: "다른 이름으로 검색하거나\n직접 등록해보세요.", actionTitle: "음식 직접 등록", action: {})
        StateView(kind: .error, title: "불러오지 못했어요", message: "네트워크를 확인하고 다시 시도해주세요.", actionTitle: "다시 시도", action: {})
    }
}
