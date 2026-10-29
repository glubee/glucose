//
//  RecordsView.swift
//  glucose
//
//  기록 탭·전체 기록 시트가 공유하는 날짜별 목록과 분류 필터. 아래로 내리면 더 불러온다.
//

import SwiftUI

struct RecordsView: View {
    var showsCloseButton = true
    @State private var viewModel = RecordsViewModel()
    @State private var filter: RecordFilter = .all
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filters
                if RecordDataSource.isPreview {
                    Text("예시 기록 · 서버에 저장되지 않아요")
                        .font(.caption1).foregroundStyle(Color.textSecondary).padding(.vertical, Spacing.xs)
                }
                Group {
                    if viewModel.isInitialLoading {
                        StateView(kind: .loading, title: "기록을 불러오고 있어요")
                    } else if viewModel.items.isEmpty {
                        if case .error(let message) = viewModel.state {
                            StateView(kind: .error, title: "기록을 불러오지 못했어요", message: message,
                                      actionTitle: "다시 시도") { Task { await viewModel.refresh() } }
                        } else {
                            StateView(kind: .empty, title: filter == .all ? "아직 기록이 없어요" : "\(filter.title) 기록이 없어요",
                                      message: filter == .response ? "저혈당 처치와 음주로 남긴 기록이 여기에 보여요." : "다른 종류의 기록은 위의 필터에서 볼 수 있어요.")
                        }
                    } else {
                        list.id(filter)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.canvas)
            .navigationTitle(showsCloseButton ? "전체 기록" : "기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                }
            }
            .navigationDestination(for: RecordItem.self) { item in
                RecordDetailView(item: item)
            }
            .task(id: "\(filter.rawValue)-\(RecordChanges.shared.revision)") { await viewModel.load(filter: filter) }
        }
    }

    private var filters: some View {
        HStack(spacing: 4) {
            ForEach(RecordFilter.allCases, id: \.self) { option in
                Button { filter = option } label: {
                    Text(option.title).font(.body2.weight(filter == option ? .bold : .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(filter == option ? Color.textPrimary : Color.textSecondary)
                        .background(filter == option ? Color.canvas : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recordFilter-\(option.rawValue)")
                .accessibilityAddTraits(filter == option ? .isSelected : [])
            }
        }
        .padding(4).background(Color.surfaceMuted, in: Capsule())
        .padding(.horizontal, Spacing.gutter).padding(.vertical, Spacing.xs)
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
                    ForEach(group.items, id: \.timelineID) { item in
                        NavigationLink(value: item) {
                            RecordRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("recordRow-\(item.timelineID)")
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
