//
//  FoodRecordSheet.swift
//  glucose
//
//  홈의 "음식 찍기"(v5 음식 기록 시트). "저혈당 대응으로 기록"을 맨 위에 둬서
//  저혈당 때 화면 아래 칩까지 내려가지 않게 했다. 양이나 처치 방법은 권하지 않는다.
//  음식 검색은 서버 API가 생기면 추가한다.
//

import SwiftUI

struct PhotoCaptureRequest: Identifiable {
    let context: IntakeContext
    let opensCamera: Bool
    var id: String { "\(context.rawValue)-\(opensCamera)" }
}

struct FoodRecordSheet: View {
    let onChoose: (PhotoCaptureRequest) -> Void
    let onWrite: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(onWrite: @escaping () -> Void, onChoose: @escaping (PhotoCaptureRequest) -> Void) {
        self.onWrite = onWrite
        self.onChoose = onChoose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SheetHeader(title: "음식 기록", subtitle: "지난 식사도 기록할 수 있어요.", onClose: { dismiss() })
                .padding(.bottom, Spacing.xs)

            option(icon: "drop.fill", title: "저혈당 대응으로 기록", subtitle: "먹은 것만 찍어서 바로 남겨요",
                   tone: .mint, request: PhotoCaptureRequest(context: .hypoTreatment, opensCamera: true))
            option(icon: "camera", title: "찍기", subtitle: "음식이 화면 가운데 오게 찍어주세요",
                   tone: .plain, request: PhotoCaptureRequest(context: .meal, opensCamera: true))
            option(icon: "photo.on.rectangle", title: "앨범에서 고르기", subtitle: "찍어둔 사진으로 기록해요",
                   tone: .plain, request: PhotoCaptureRequest(context: .meal, opensCamera: false))
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: onWrite)
            } label: {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("글로 남기기").font(.headline2)
                        Text("사진 없이 먹은 음식과 시각을 적어요.")
                            .font(.caption1).foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.textPrimary)
                .card(padding: Spacing.s)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(Spacing.gutter)
        .presentationDetents([.large])
    }

    private func option(icon: String, title: String, subtitle: String, tone: CardTone,
                        request: PhotoCaptureRequest) -> some View {
        Button {
            dismiss()
            // 시트가 닫힌 뒤에 다음 화면을 띄운다
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onChoose(request) }
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tone == .mint ? Color.mintStrong : Color.textPrimary)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline2).foregroundStyle(Color.textPrimary)
                    Text(subtitle).font(.caption1).foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
            }
            .card(tone, padding: Spacing.s)
        }
        .buttonStyle(.plain)
    }
}
