//
//  OnboardingStepContent.swift
//  glucose
//
//  온보딩 입력칸 안의 단계별 내용(디자이너 v5 프로토타입의 크기·색 그대로).
//

import SwiftUI

struct OnboardingStepContent: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        Group {
            switch viewModel.step {
            case .hello, .signIn:
                EmptyView()
            case .name:
                NameField(viewModel: viewModel)
            case .howTo:
                HowToRows(viewModel: viewModel)
            case .insulin:
                InsulinFields(viewModel: viewModel)
            case .dayClose:
                DayCloseWheel(viewModel: viewModel)
            case .notifications:
                Label("알림에는 혈당·음식·인슐린 내용이 나오지 않아요.", systemImage: "lock")
                    .font(.caption1)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 14))
            case .widget:
                WidgetGuide()
            }
        }
        .transition(.opacity.combined(with: .offset(y: 6)))
    }
}

/// "부를 이름" — 크게, 노란 테두리. 자판은 칸을 눌렀을 때만 올라오고, 완료 키는 다음으로 넘어간다
private struct NameField: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("부를 이름")
                .font(.pretendard(13, relativeTo: .footnote, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            TextField("", text: $viewModel.nickname)
                .font(.pretendard(20, relativeTo: .title3, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .textContentType(.nickname)
                .submitLabel(.next)
                .focused($focused)
                .onSubmit { Task { await viewModel.primary() } }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, 14)
                .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(focused ? Color.brand : Color.line, lineWidth: 2))
                .onChange(of: viewModel.nickname) { _, value in
                    if value.count > 10 { viewModel.nickname = String(value.prefix(10)) }
                    viewModel.nicknameChanged()
                }
            Text("이름 없이도 쓸 수 있어요.")
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

/// 쓰는 법 3줄. 누르면 글루비 동작이 바뀐다
private struct HowToRows: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var appeared = false

    private let rows = [("먹을 때 찰칵", "위젯을 누르면 카메라가 바로 열려요"),
                        ("맞을 때 \"투여 확인\"", "평소 값이 미리 채워져 있어요"),
                        ("밤에 그래프 올리기", "리브레 그래프와 낮 기록을 맞춰봐요")]

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                Button { viewModel.selectHowTo(index) } label: {
                    HStack(spacing: Spacing.s) {
                        Text("\(index + 1)")
                            .font(.pretendard(13, relativeTo: .footnote, weight: .bold))
                            .foregroundStyle(Color.onButton)
                            .frame(width: 26, height: 26)
                            .background(Color.buttonFill, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.0).font(.pretendard(15, relativeTo: .subheadline, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                            Text(row.1).font(.pretendard(14, relativeTo: .subheadline))
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(viewModel.howToSelection == index ? Color.brandSoft : Color.surfaceMuted,
                                in: RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(viewModel.howToSelection == index ? Color.brand : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                // 한 줄씩 떠오른다
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)
                .animation(.easeOut(duration: 0.5).delay(0.15 + Double(index) * 0.14), value: appeared)
                .accessibilityAddTraits(viewModel.howToSelection == index ? .isSelected : [])
            }
        }
        .onAppear { appeared = true }
    }
}

/// 평소 인슐린: 연보라 상자에 제품 이름 + 단위
private struct InsulinFields: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(viewModel.insulins) { insulin in
                Label("\(insulin.name)\(insulin.units.map { " · \($0.formatted(.number.precision(.fractionLength(0...1))))U" } ?? "")",
                      systemImage: "checkmark")
                    .font(.pretendard(14, relativeTo: .subheadline, weight: .semibold))
                    .foregroundStyle(Color.insulin)
            }
            HStack(spacing: Spacing.xs) {
                TextField("제품 이름", text: $viewModel.insulinName)
                    .accessibilityLabel("제품 이름")
                    .padding(.horizontal, Spacing.s).padding(.vertical, 10)
                    .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.field))
                TextField("단위", text: $viewModel.insulinUnits)
                    .keyboardType(.decimalPad)
                    .accessibilityLabel("평소 단위")
                    .padding(.horizontal, Spacing.s).padding(.vertical, 10)
                    .frame(width: 96)
                    .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.field))
            }
            .font(.pretendard(16, relativeTo: .body, weight: .bold))
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, 14)
            .background(Color.insulinSoft, in: RoundedRectangle(cornerRadius: Radius.card))

            Button("+ 인슐린 추가") { viewModel.addInsulin() }
                .font(.pretendard(15, relativeTo: .subheadline, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .disabled(viewModel.insulinName.trimmingCharacters(in: .whitespaces).isEmpty)

            Text("내가 입력한 값을 기억해 두는 것뿐이에요. 앱이 용량을 정하거나 권하지 않아요.")
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

/// 하루 마무리 시각: 30분씩, 가운데 큰 숫자
private struct DayCloseWheel: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var direction: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            Button(OnboardingViewModel.timeText((viewModel.dayCloseMinutes + 1410) % 1440)) { shift(-30) }
                .accessibilityLabel("30분 앞으로")
                .font(.pretendard(22, relativeTo: .title2, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(height: 38)
            Text(OnboardingViewModel.timeText(viewModel.dayCloseMinutes))
                .font(.pretendard(44, relativeTo: .largeTitle, weight: .heavy))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(viewModel.dayCloseMinutes)))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 200, height: 58)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.card))
                .accessibilityLabel("하루 마무리 \(OnboardingViewModel.timeText(viewModel.dayCloseMinutes))")
            Button(OnboardingViewModel.timeText((viewModel.dayCloseMinutes + 30) % 1440)) { shift(30) }
                .accessibilityLabel("30분 뒤로")
                .font(.pretendard(22, relativeTo: .title2, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(height: 38)
            Text("나중에 설정에서 바꿀 수 있어요.")
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
                .padding(.top, Spacing.xs)
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: viewModel.dayCloseMinutes)
    }

    private func shift(_ minutes: Int) {
        withAnimation(.spring(duration: 0.35)) { viewModel.shiftDayClose(byMinutes: minutes) }
    }
}

/// 위젯 붙이는 법 3칸 + 위젯 미리보기
private struct WidgetGuide: View {
    private let steps = [("1", "홈 화면\n길게 누르기"), ("2", "왼쪽 위\n+ 누르기"), ("3", "\"글루비\"\n고르기")]
    @State private var showGuide = false

    var body: some View {
        VStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                ForEach(steps, id: \.0) { step in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.0).font(.pretendard(16, relativeTo: .body, weight: .bold))
                        Text(step.1).font(.pretendard(13, relativeTo: .footnote, weight: .semibold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.s).padding(.vertical, 10)
                    .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            HStack(spacing: 10) {
                Image("face_calm").resizable().scaledToFit().frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                Text("연속 \(DayCloseStore.shared.streak(endingAt: .now))일")
                    .font(.pretendard(18, relativeTo: .headline, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: 0)
                pill("찍기", fill: .brand, text: .onBrand)
                pill("인슐린", fill: .surfaceMuted, text: .textPrimary)
            }
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.line, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("위젯 미리보기: 연속일과 찍기, 인슐린 버튼")
            Button("위젯 자세히 보기") { showGuide = true }
                .font(.caption1.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(minHeight: Metrics.minTapTarget)
        }
        .sheet(isPresented: $showGuide) {
            NavigationStack {
                WidgetGuideView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { showGuide = false } } }
            }
        }
    }

    private func pill(_ title: String, fill: Color, text: Color) -> some View {
        Text(title)
            .font(.pretendard(14, relativeTo: .subheadline, weight: .bold))
            .foregroundStyle(text)
            .padding(.horizontal, Spacing.s).padding(.vertical, 9)
            .background(fill, in: RoundedRectangle(cornerRadius: 18))
    }
}
