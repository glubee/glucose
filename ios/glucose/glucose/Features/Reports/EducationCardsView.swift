import SwiftUI

/// 일일 카드와 상시 안내가 동일한 원문·출처·검토 정보를 보여준다.
struct GuidanceCardContent: View {
    let card: DailyReport.EducationCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.title).font(.headline2)
            Text(card.body).font(.body2)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(card.sources ?? []) { source in
                if source.kind == "APP_GUIDE" {
                    DisclosureGroup(source.name) {
                        Text("글루비는 업로드한 그래프 이미지에서 읽힌 구간으로 리포트를 만들어요. 끊긴 구간은 비워 두고, 그래프 위·아래 끝에 닿은 수치는 정확한 값을 알기 어려운 구간으로 표시해요. 리포트 카드가 나타나는 숫자 조건은 앱의 표시 규칙이며, 개인의 치료 목표를 뜻하지 않아요.")
                            .font(.caption1)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .font(.caption1)
                } else if let value = source.url, let url = URL(string: value), url.scheme == "https" {
                    Link(destination: url) {
                        Label(source.name, systemImage: "arrow.up.right.square")
                            .font(.caption1)
                    }
                }
            }
            if let reviewer = card.reviewedBy, let date = card.reviewedAt {
                Text("문구 검토: \(reviewer) · \(date)")
                    .font(.sectionLabel)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, 6)
        .buttonStyle(.borderless)
    }
}

struct EducationCardsView: View {
    @AppStorage("guidance.nextCardIndex") private var nextCardIndex = 0
    @State private var cards: [DailyReport.EducationCard] = []
    @State private var selectedIndex = 0
    @State private var selectedInitialCard = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView("안내를 불러오고 있어요")
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
                Button("다시 시도") { Task { await load() } }
            } else if cards.isEmpty {
                Text("등록된 안내가 아직 없어요.").foregroundStyle(.secondary)
            } else {
                Section("이번에 읽어볼 안내") {
                    GuidanceCardContent(card: cards[selectedIndex])
                    if cards.count > 1 {
                        HStack {
                            Text("\(selectedIndex + 1) / \(cards.count)")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("다음 안내", systemImage: "arrow.right") {
                                selectedIndex = (selectedIndex + 1) % cards.count
                                nextCardIndex = (selectedIndex + 1) % cards.count
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Section("모든 안내") {
                    ForEach(cards) { card in
                        NavigationLink {
                            List { GuidanceCardContent(card: card) }
                                .navigationTitle("안내")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Text(card.title)
                        }
                    }
                }
            }
        }
        .navigationTitle("알아두면 좋은 정보")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded: [DailyReport.EducationCard] = try await APIClient.shared.send(path: "/v1/education-cards/review")
            guard !Task.isCancelled else { return }
            cards = loaded
            if !cards.isEmpty {
                if !selectedInitialCard {
                    selectedIndex = max(0, nextCardIndex) % cards.count
                    nextCardIndex = (selectedIndex + 1) % cards.count
                    selectedInitialCard = true
                } else {
                    selectedIndex = min(selectedIndex, cards.count - 1)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "안내를 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
        }
        isLoading = false
    }
}
