import SwiftUI

struct ChartPhotoBadge: View {
    let group: ChartPhotoGroup
    var size: CGFloat = 44

    var body: some View {
        FoodPhotoThumbnail(photoId: group.photoId, size: size)
            .overlay(RoundedRectangle(cornerRadius: size * 0.25).strokeBorder(group.members[0].mark.context.tint, lineWidth: 2.5))
            .overlay(alignment: .topTrailing) {
                if group.members.count > 1 {
                    Text("+\(group.members.count - 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.onButton)
                        .padding(3)
                        .background(Color.buttonFill, in: Capsule())
                        .offset(x: 5, y: -4)
                }
            }
            .accessibilityHidden(true)
    }
}

struct ChartPhotoTimeline: View {
    let groups: [ChartPhotoGroup]
    let onSelect: (ChartPhotoGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("사진 기록 · 누르면 크게 볼 수 있어요")
                .font(.caption1)
                .foregroundStyle(Color.textSecondary)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Spacing.s) {
                    ForEach(groups) { group in
                        Button { onSelect(group) } label: {
                            VStack(spacing: 5) {
                                ChartPhotoBadge(group: group, size: 48)
                                Text(ReportDay.timeString(from: group.time)).font(.caption1.weight(.semibold))
                                if group.anchorValue == nil {
                                    Text("그래프 비어 있음").font(.caption2)
                                }
                            }
                            .foregroundStyle(Color.textSecondary)
                            .padding(6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("\(ReportDay.timeString(from: group.time)) 음식 사진 \(group.members.count)장\(group.anchorValue == nil ? ", 그래프 비어 있음" : "")")
                        .accessibilityIdentifier("photoTimeline-\(ReportDay.timeString(from: group.time))")
                    }
                }
                .padding(.top, 5)
            }
        }
    }
}
