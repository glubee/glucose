//
//  WidgetGuideView.swift
//  glucose
//
//  위젯 안내: 종류별로 하는 일, 홈 화면·잠금 화면에 더하는 법, 위젯으로 찍은 사진이 어디로 가는지,
//  잠금 화면에는 무엇이 보이는지. 설정과 온보딩 위젯 단계에서 연다(docs: ux-improvements 6장).
//

import SwiftUI

struct WidgetGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader(title: "위젯 종류")
                    kind("square.grid.2x2", "빠른 기록 (중간)", "연속일을 보면서 사진 찍기·인슐린 투여 확인을 한 번에 열어요.")
                    kind("camera.fill", "사진 찍기 (작은)", "누르면 바로 카메라가 열려요. 찍고 바로 닫아도 돼요.")
                    kind("syringe.fill", "인슐린 (작은)", "누르면 평소 인슐린이 채워진 투여 확인이 열려요.")
                    kind("lock.fill", "연속 완성일 (잠금 화면)", "잠금 화면에서 글루비 얼굴과 연속일을 봐요.")
                }
                .card()

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader(title: "홈 화면에 더하기")
                    steps(["홈 화면 빈 곳을 길게 눌러요", "왼쪽 위 + 를 눌러요", "\"글루비\"를 찾아 원하는 크기를 골라요"])
                }
                .card()

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader(title: "잠금 화면에 더하기")
                    steps(["잠금 화면을 길게 눌러 \"사용자화\"를 눌러요", "잠금 화면을 고르고 시계 아래 칸을 눌러요", "\"글루비\"에서 원형이나 직사각형을 골라요"])
                }
                .card()

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader(title: "위젯으로 찍은 사진은요")
                    Label("찍으면 기기에 먼저 저장되고, 앱을 열면 올라가서 어떤 음식인지 미리 알아봐요.", systemImage: "1.circle.fill")
                    Label("홈의 \"확인 안 한 사진\"이나 밤의 하루 마무리에서 음식이 맞는지 확인하면 기록이 돼요.", systemImage: "2.circle.fill")
                    Label("확인하기 전에는 리포트에 들어가지 않아요.", systemImage: "3.circle.fill")
                }
                .font(.body2)
                .foregroundStyle(Color.textPrimary)
                .card(.brand)

                Label("잠금 화면과 위젯에는 연속일과 글루비 얼굴만 보여요. 혈당이나 먹은 음식은 보이지 않아요.",
                      systemImage: "eye.slash")
                    .font(.body2)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.m)
        }
        .background(Color.canvas)
        .navigationTitle("위젯 안내")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func kind(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.onBrandSoft)
                .frame(width: 40, height: 40)
                .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: Radius.field))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline2).foregroundStyle(Color.textPrimary)
                Text(detail).font(.body2).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func steps(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text("\(index + 1)")
                        .font(.caption1.weight(.bold))
                        .foregroundStyle(Color.onButton)
                        .frame(width: 22, height: 22)
                        .background(Color.buttonFill, in: Circle())
                    Text(item).font(.body2).foregroundStyle(Color.textPrimary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { WidgetGuideView() }
}
