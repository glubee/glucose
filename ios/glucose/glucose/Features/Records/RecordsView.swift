//
//  RecordsView.swift
//  glucose
//
//  전체 기록(v5): 날짜별로 묶은 카드 목록. 리포트의 목록 버튼에서 연다. 아래로 내리면 더 불러온다.
//

import SwiftUI

struct RecordsView: View {
    @State private var viewModel = RecordsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isInitialLoading {
                    StateView(kind: .loading, title: "기록을 불러오고 있어요")
                } else if viewModel.items.isEmpty {
                    if case .error(let message) = viewModel.state {
                        StateView(kind: .error, title: "기록을 불러오지 못했어요", message: message,
                                  actionTitle: "다시 시도") { Task { await viewModel.refresh() } }
                    } else {
                        StateView(kind: .empty, title: "아직 기록이 없어요",
                                  message: "음식을 찍거나 인슐린을 기록하면 여기에 쌓여요.")
                    }
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.canvas)
            .navigationTitle("전체 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .navigationDestination(for: RecordItem.self) { item in
                RecordDetailView(item: item)
            }
            .task(id: RecordChanges.shared.revision) { await viewModel.load() }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(days, id: \.day) { group in
                    Text(dayTitle(group.day))
                        .font(.sectionLabel)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, Spacing.m)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.items) { item in
                        NavigationLink(value: item) {
                            RecordRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            Task { await viewModel.loadMoreIfNeeded(currentItem: item) }
                        }
                    }
                }
                if viewModel.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, Spacing.m)
                }
                if case .error(let message) = viewModel.state {
                    HStack {
                        Text(message).font(.caption1).foregroundStyle(Color.alert)
                        Spacer()
                        Button("다시 시도") { Task { await viewModel.refresh() } }
                            .font(.caption1.weight(.semibold))
                    }
                    .card(padding: Spacing.s)
                    .padding(.top, Spacing.s)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.l)
        }
        .refreshable { await viewModel.refresh() }
    }

    /// 최신 날짜부터, 같은 날 안에서는 기존 순서(최신 먼저) 그대로
    private var days: [(day: Date, items: [RecordItem])] {
        let calendar = ReportDay.calendar
        var groups: [(day: Date, items: [RecordItem])] = []
        for item in viewModel.items {
            let day = calendar.startOfDay(for: item.occurredAt)
            if let last = groups.indices.last, groups[last].day == day {
                groups[last].items.append(item)
            } else {
                groups.append((day, [item]))
            }
        }
        return groups
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = ReportDay.calendar
        if calendar.isDateInToday(day) { return "오늘" }
        if calendar.isDateInYesterday(day) { return "어제" }
        return ReportDay.displayString(from: day)
    }
}

#Preview {
    RecordsView()
}
