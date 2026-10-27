//
//  DesignCatalogView.swift
//  glucose
//
//  디자인 기본값 확인용 화면. 앱에서는 열지 않고 Xcode 프리뷰로만 본다.
//

#if DEBUG
import SwiftUI

struct DesignCatalogView: View {
    private let colors: [(String, Color)] = [
        ("brand", .brand), ("onBrand", .onBrand), ("brandSoft", .brandSoft), ("brandSofter", .brandSofter),
        ("mintSoft", .mintSoft), ("mintStrong", .mintStrong), ("insulinSoft", .insulinSoft), ("insulin", .insulin),
        ("alert", .alert), ("textPrimary", .textPrimary), ("textSecondary", .textSecondary),
        ("canvas", .canvas), ("surfaceMuted", .surfaceMuted), ("line", .line),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                section("버튼") {
                    Button("기록 저장") {}.buttonStyle(.glubeePrimary)
                    Button("아니에요") {}.buttonStyle(.glubeeSecondary)
                    Button("오늘 정리 마치기") {}.buttonStyle(.glubeeMuted)
                }

                section("칩") {
                    ChipSamples()
                }

                section("카드·머리말") {
                    SheetHeader(title: "음식 기록", subtitle: "지난 식사도 기록할 수 있어요.", onClose: {})
                    SectionHeader(title: "최근 기록한 음식", subtitle: "음식을 선택해 양을 확인하세요.", trailing: "3개")
                    Text("식사 전체 · 2가지 음식").card(.brand)
                    Text("인슐린 투여 · 2U").card(.insulin)
                }

                section("글루비 말풍선") {
                    BeeSpeech(pose: .curious, text: "점심엔 뭘 드셨어요?")
                    BeeSpeech(pose: .think, text: "사과랑 우유로 보이는데, 맞나요?", tone: .brand)
                }

                section("상태") {
                    StateView(kind: .empty, title: "음식을 찾지 못했어요.", actionTitle: "음식 직접 등록", action: {})
                        .card()
                }

                section("색") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: Spacing.s) {
                        ForEach(colors, id: \.0) { name, color in
                            VStack(spacing: Spacing.xxs) {
                                RoundedRectangle(cornerRadius: Radius.field)
                                    .fill(color)
                                    .frame(height: 48)
                                    .overlay(RoundedRectangle(cornerRadius: Radius.field).stroke(Color.line))
                                Text(name).font(.caption2).foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }

                section("글꼴") {
                    Text("연속 12일").font(.display)
                    Text("오늘의 흐름을 함께 볼까요?").font(.headline1)
                    Text("혈당 흐름").font(.headline2)
                    Text("사진 분석으로 추정한 값이에요.").font(.body1)
                    Text("10월 5일 21:47 · 리브레에서 가져옴").font(.body2)
                    Text("범위 70–180 mg/dL").font(.caption1)
                }
                .foregroundStyle(Color.textPrimary)

                section("글루비") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: Spacing.s) {
                        ForEach(MascotPose.allCases, id: \.self) { pose in
                            MascotView(pose: pose, size: 72)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.l)
        }
        .background(Color.canvas)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title.uppercased())
                .font(.sectionLabel)
                .foregroundStyle(Color.textSecondary)
            content()
        }
    }
}

#Preview("라이트") {
    DesignCatalogView()
}

#Preview("다크") {
    DesignCatalogView().preferredColorScheme(.dark)
}

#Preview("큰 글씨") {
    DesignCatalogView().environment(\.dynamicTypeSize, .accessibility2)
}
#endif
