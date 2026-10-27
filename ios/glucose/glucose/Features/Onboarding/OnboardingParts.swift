//
//  OnboardingParts.swift
//  glucose
//
//  쓰는 법 카드(설정의 도움말에서 쓴다).
//

import SwiftUI

struct HowToCard: View {
    private let items: [(icon: String, title: String, detail: String)] = [
        ("camera.fill", "먹을 때 찰칵", "사진 한 장이면 돼요. 확인은 나중에 해요."),
        ("syringe.fill", "맞을 때 한 번", "평소 인슐린이 채워져 있어서 확인만 누르면 돼요."),
        ("moon.stars.fill", "밤에 같이 정리", "리브레 그래프를 올리고 빠진 기록을 채우면 하루가 완성돼요."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(items, id: \.title) { item in
                HStack(alignment: .top, spacing: Spacing.s) {
                    Image(systemName: item.icon)
                        .font(.body)
                        .foregroundStyle(Color.onBrand)
                        .frame(width: 36, height: 36)
                        .background(Color.brand, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.headline2).foregroundStyle(Color.textPrimary)
                        Text(item.detail).font(.body2).foregroundStyle(Color.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}
