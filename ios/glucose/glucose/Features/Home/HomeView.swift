//
//  HomeView.swift
//  glucose
//
//  홈(디자이너 v5 프로토타입): "민지님, / 연속 N일"(숫자가 올라가며 나타남) + 노란 말풍선(한 글자씩) + 큰 글루비,
//  이번 주 벌집, 꿀단지, 그 아래로 화면 끝까지 이어지는 "오늘의 다이어리" 줄노트 시간줄. 아래에 기록·마무리 버튼.
//  확인 대기 사진도 시간줄 안에 바로 보인다(따로 띠를 두지 않음). 오늘 그래프는 리포트에서 본다.
//  쉬어가는 중이면 쉬는 화면.
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var showFoodSheet = false
    @State private var showManualFood = false
    @State private var photoCapture: PhotoCaptureRequest?
    @State private var showInsulin = false
    @State private var showPendingPhotos = false
    @State private var shownStreak = 0
    @State private var selectedPendingPhoto: PendingPhoto?
    @State private var showAllRecords = false
    @State private var highlightedID: String?
    /// 지난 날 다이어리에서 연 하루 마무리
    @State private var pastDayClose: DayToClose?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.rest != nil {
                    restingContent
                } else {
                    content
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RecordItem.self) { item in
                RecordDetailView(item: item).toolbar(.visible, for: .navigationBar)
            }
        }
        .background(Color.canvas)
        .task(id: RecordChanges.shared.revision) {
            await viewModel.refresh()
            countUp()
        }
        .sheet(isPresented: $showFoodSheet) {
            FoodRecordSheet(onWrite: { showManualFood = true }) { request in photoCapture = request }
        }
        .sheet(isPresented: $showManualFood, onDismiss: refresh) { FoodRecordFormView() }
        .sheet(item: $photoCapture, onDismiss: refresh) { request in
            PhotoCaptureView(context: request.context, opensCamera: request.opensCamera)
        }
        .sheet(isPresented: $showInsulin, onDismiss: refresh) { InsulinConfirmView() }
        .fullScreenCover(item: $pastDayClose, onDismiss: { Task { await viewModel.refresh() } }) { item in
            DayCloseView(day: item.day)
        }
        .sheet(isPresented: $showPendingPhotos, onDismiss: refresh) { PendingPhotosView(store: viewModel.photos) }
        .sheet(isPresented: $showAllRecords) { RecordsView() }
        .sheet(item: $selectedPendingPhoto, onDismiss: refresh) { photo in
            NavigationStack {
                PendingPhotoDetailView(photoID: photo.id, store: viewModel.photos) { selectedPendingPhoto = nil }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .onChange(of: viewModel.photos.photos.map(\.id)) { previous, current in
            if let id = current.last(where: { !previous.contains($0) }) {
                viewModel.timeline.requestPhotoFocus(id, photos: viewModel.photos.photos)
            }
        }
    }

    /// 기록 시트를 닫은 뒤: 새 기록이 붙은 오늘 다이어리로 돌아온다
    private func refresh() { Task { await viewModel.refresh(returnToToday: true) } }

    private var focusTriggerID: String? {
        let router = DeepLinkRouter.shared
        let presented = showFoodSheet || showManualFood || photoCapture != nil || showInsulin || showPendingPhotos
            || selectedPendingPhoto != nil || showAllRecords || router.showsQuickCapture
            || router.showsInsulinRecord || router.showsDayClose
        return presented ? nil : viewModel.timeline.focusID
    }

    /// 오늘을 보고 있으면 평소처럼(아침 유예 시간엔 어제), 지난 날을 보고 있으면 그날을 마무리한다
    private func openDayClose() {
        if viewModel.isDiaryToday {
            DeepLinkRouter.shared.handle(URL(string: "glubee://day-close")!)
        } else {
            pastDayClose = DayToClose(day: viewModel.diaryDay)
        }
    }

    private struct DayToClose: Identifiable {
        let day: Date
        var id: Date { day }
    }

    private var pastDayCloseTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = ReportDay.calendar.timeZone
        formatter.dateFormat = "M월 d일"
        let day = formatter.string(from: viewModel.diaryDay)
        // 데모 재현 날(DEBUG)은 마무리한 뒤에도 처음부터 다시 할 수 있다
        if viewModel.isDiaryDayClosed && !DayCloseViewModel.isDemoReplay(viewModel.diaryDay) {
            return "\(day) 마무리 다시 보기"
        }
        return "\(day) 마무리하기"
    }

    /// 연속 숫자가 0부터 올라가며 나타난다
    private func countUp() {
        let target = viewModel.streak
        guard !reduceMotion, target > 0 else { shownStreak = target; return }
        shownStreak = 0
        withAnimation(.easeOut(duration: 0.7)) { shownStreak = target }
    }

    // MARK: - 평소

    private var content: some View {
        let mood = viewModel.mood()
        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                  VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center, spacing: Spacing.xs) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(viewModel.nickname.isEmpty ? "오늘의 흐름을 함께 볼까요?" : "\(viewModel.nickname)님,")
                                    .font(.pretendard(17, relativeTo: .headline, weight: .medium))
                                    .foregroundStyle(Color.textSecondary)
                                StreakNumber(value: shownStreak)
                                TypingText(text: mood.line)
                                    .font(.pretendard(14, relativeTo: .subheadline, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                                    .padding(.horizontal, Spacing.s)
                                    .padding(.vertical, Spacing.xs)
                                    .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 14))
                                    .frame(maxWidth: 220, alignment: .leading)
                                    .padding(.top, Spacing.xxs)
                                    .accessibilityLabel("글루비: \(mood.line)")
                            }
                            Spacer(minLength: 0)
                            MascotView(pose: mood.pose, size: 132, motion: mood.motion, floats: true)
                        }

                        WeekHoneycomb(states: viewModel.weekStates)
                            .padding(.top, 14)

                        if viewModel.honeypots > 0 {
                            HStack(spacing: 6) {
                                HStack(spacing: 2) {
                                    ForEach(0..<viewModel.honeypots, id: \.self) { _ in HoneypotIcon() }
                                }
                                Text("꿀단지 \(viewModel.honeypots)개 · 하루를 놓쳐도 연속을 지켜줘요")
                                    .font(.pretendard(13, relativeTo: .footnote, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                            }
                            .padding(.horizontal, Spacing.s)
                            .padding(.vertical, 7)
                            .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.field))
                            .padding(.top, Spacing.s)
                            .accessibilityElement(children: .combine)
                        }

                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, Spacing.m)
                    .padding(.bottom, Spacing.m)

                    // 오늘의 다이어리: 하루 마무리와 같은 줄노트가 화면 끝까지 이어진다(Dave 2026-10-29)
                    HomeTimelineSection(viewModel: viewModel, highlightedID: highlightedID,
                        openPending: { selectedPendingPhoto = $0 },
                        showAll: { showAllRecords = true })
                  }
                }

                .accessibilityIdentifier("homeTimelineScroll")
                .clipped()
                .refreshable { await viewModel.refresh() }
                .task(id: focusTriggerID) {
                    guard let id = focusTriggerID else { highlightedID = nil; return }
                    guard viewModel.todayEntries.contains(where: { $0.id == id }) else {
                        viewModel.timeline.finishFocus(id); return
                    }
                    highlightedID = id
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    highlightedID = nil
                    viewModel.timeline.finishFocus(id)
                }
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button { showFoodSheet = true } label: { Label("음식 찍기", systemImage: "camera.fill") }
                        .buttonStyle(.glubeeAccent)
                    Button { showInsulin = true } label: { Label("인슐린", systemImage: "syringe.fill") }
                        .buttonStyle(.glubeeSoft)
                }
                if !viewModel.isDiaryToday {
                    Button(pastDayCloseTitle, action: openDayClose)
                        .buttonStyle(viewModel.isDiaryDayClosed && !DayCloseViewModel.isDemoReplay(viewModel.diaryDay)
                                     ? .glubeeSoft : .glubeePrimary)
                        .accessibilityIdentifier("pastDayClose")
                } else if !viewModel.isTodayClosed {
                    Button("하루 마무리하기", action: openDayClose).buttonStyle(.glubeePrimary)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
        }
    }

    // MARK: - 쉬어가는 중

    private var restingContent: some View {
        VStack(spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if !viewModel.nickname.isEmpty {
                    Text("\(viewModel.nickname)님,").font(.pretendard(17, relativeTo: .headline, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
                StreakNumber(value: viewModel.streak).opacity(0.45)
                if let reason = viewModel.rest?.reason, let end = viewModel.restEndText {
                    Label("\(reason.title) · \(end)까지 멈춤", systemImage: "pause.fill")
                        .font(.caption1)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.surfaceMuted, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
            MascotView(pose: .breakTime, size: 150, floats: true)
            Text("천천히 와도 돼요").font(.headline1).foregroundStyle(Color.textPrimary)
            Text("쉬는 동안은 연속일이 줄지 않아요.\n알림도 보내지 않아요.")
                .font(.body2).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            WeekHoneycomb(states: viewModel.weekStates)
            Spacer()
            Button("다시 시작하기") { Task { await viewModel.endRest() } }.buttonStyle(.glubeeSoft)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }
}

/// 작은 꿀단지 아이콘
private struct HoneypotIcon: View {
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.79, green: 0.54, blue: 0.23)).frame(width: 9, height: 3)
            RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.79, green: 0.54, blue: 0.23).opacity(0.85)).frame(width: 13, height: 12)
        }
        .accessibilityHidden(true)
    }
}

/// 쉬어가기: 이유와 기간(설정에서도 연다)
struct RestSheet: View {
    let onStart: (RestPeriod.Reason, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason: RestPeriod.Reason = .resting
    @State private var days = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SheetHeader(title: "쉬어가기", subtitle: "쉬는 동안은 연속일이 끊기지도 늘지도 않고, 알림도 멈춰요.",
                        onClose: { dismiss() })
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("이유").font(.body2).foregroundStyle(Color.textSecondary)
                ChipPicker(options: RestPeriod.Reason.allCases.map { ($0, $0.title) }, selection: $reason)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("기간").font(.body2).foregroundStyle(Color.textSecondary)
                ChipPicker(options: [(1, "오늘만"), (3, "3일"), (7, "일주일")], selection: $days)
            }
            Spacer()
            Button("쉬어가기 시작") {
                onStart(reason, days)
                dismiss()
            }
            .buttonStyle(.glubeePrimary)
        }
        .padding(Spacing.gutter)
        .presentationDetents([.medium])
    }
}

#Preview {
    HomeView()
}
