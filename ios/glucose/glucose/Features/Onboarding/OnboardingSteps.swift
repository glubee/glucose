//
//  OnboardingSteps.swift
//  glucose
//
//  온보딩 단계 중 입력이 있는 것들.
//

import SwiftUI

struct OnboardingNameStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        TextField("부를 이름", text: $viewModel.nickname)
            .font(.headline2)
            .textContentType(.nickname)
            .submitLabel(.done)
            .focused($focused)
            .onSubmit { viewModel.commitName() }
            .padding(Spacing.m)
            .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.field))
            .onAppear { focused = true }
    }
}

struct OnboardingHowToStep: View {
    private let items: [(icon: String, title: String, detail: String)] = [
        ("camera.fill", "먹을 때 찰칵", "위젯이나 홈에서 사진 한 장. 확인은 나중에 해요."),
        ("syringe.fill", "맞을 때 한 번", "평소 인슐린이 채워져 있어서 확인만 누르면 돼요."),
        ("moon.stars.fill", "밤에 같이 정리", "리브레 그래프를 올리고 빠진 기록을 채우면 하루가 완성돼요."),
    ]

    var body: some View {
        VStack(spacing: Spacing.s) {
            ForEach(items, id: \.title) { item in
                HStack(alignment: .top, spacing: Spacing.m) {
                    Image(systemName: item.icon)
                        .font(.title3)
                        .foregroundStyle(Color.onBrand)
                        .frame(width: 44, height: 44)
                        .background(Color.brand, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(item.title).font(.headline2).foregroundStyle(Color.textPrimary)
                        Text(item.detail).font(.body2).foregroundStyle(Color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct OnboardingInsulinStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var name = ""
    @State private var unitsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(viewModel.insulins) { insulin in
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(insulin.name).font(.headline2)
                        Text(insulin.units.map { "평소 \(format($0))U" } ?? "단위는 그때그때 입력")
                            .font(.body2).foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Button {
                        viewModel.removeInsulin(insulin)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                    }
                    .accessibilityLabel("\(insulin.name) 지우기")
                }
                .card(.insulin, padding: Spacing.s)
            }

            VStack(spacing: Spacing.xs) {
                TextField("제품 이름 (예: 초속효성 인슐린)", text: $name)
                Divider()
                TextField("평소 단위 (선택)", text: $unitsText)
                    .keyboardType(.decimalPad)
            }
            .font(.body1)
            .textFieldStyle(.plain)
            .padding(Spacing.m)
            .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.field))

            Button("추가") {
                viewModel.addInsulin(name: name, units: Double(unitsText.replacingOccurrences(of: ",", with: ".")))
                name = ""
                unitsText = ""
            }
            .buttonStyle(.glubeeSecondary)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

            Text("내가 입력한 값을 그대로 채워둘 뿐, 글루비가 용량을 정하거나 추천하지 않아요.")
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func format(_ units: Double) -> String {
        units.formatted(.number.precision(.fractionLength(0...1)))
    }
}

struct OnboardingWidgetStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label("홈 화면 빈 곳을 길게 누르기", systemImage: "hand.tap")
            Label("왼쪽 위 + 또는 편집 → 위젯 추가", systemImage: "plus.circle")
            Label("'글루비' 검색해서 추가", systemImage: "magnifyingglass")
        }
        .font(.body1)
        .foregroundStyle(Color.textPrimary)
        .card(.mint)
    }
}
