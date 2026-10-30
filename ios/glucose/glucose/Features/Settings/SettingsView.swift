//
//  SettingsView.swift
//  glucose
//
//  설정(v5): 나(이름) · 기록 관리(평소 인슐린, 혈당 가져오기) · 알림(하루 마무리 시각, 권한, 끼니·사진 알림) ·
//  쉬어가기 · 도움말 · 계정. 온보딩에서 정한 값은 모두 여기서 바꾼다.
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var preferences = UserPreferences.shared
    @State private var store = DayCloseStore.shared
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showGraphUpload = false
    @State private var showRest = false
    @State private var showHelp = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Environment(\.openURL) private var openURL
    #if DEBUG
    @State private var demoStatus: String?
    @State private var demoRunning = false
    /// 실제 기록을 백업할 날(기본: 데모 영상에 쓰는 실제 하루, 2026-10-29)
    @State private var backupDay = ReportDay.date(fromAPIString: "2026-10-29") ?? .now
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Spacing.s) {
                        MascotView(pose: .wave, size: 48, motion: .none)
                        TextField("부를 이름", text: Binding(
                            get: { preferences.nickname },
                            set: { preferences.nickname = $0 }
                        ))
                        .font(.headline2)
                    }
                } footer: {
                    Text("글루비가 부르는 이름이에요. 기기에만 저장돼요.")
                }

                Section("기록 관리") {
                    NavigationLink {
                        UsualInsulinEditor()
                    } label: {
                        row("평소 사용하는 인슐린",
                            preferences.usualInsulins.isEmpty ? "아직 등록하지 않았어요"
                                : preferences.usualInsulins.map(\.name).joined(separator: ", "))
                    }
                    Button { showGraphUpload = true } label: {
                        row("혈당 가져오기", "리브레에서 혈당 그래프를 가져와요.")
                    }
                    .tint(Color.textPrimary)
                }

                Section {
                    DatePicker("하루 마무리 시각", selection: dayCloseBinding, displayedComponents: .hourAndMinute)
                    if notificationStatus != .authorized {
                        Button("알림 켜기") { Task { await enableNotifications() } }
                    }
                } header: {
                    Text("알림")
                } footer: {
                    Text(notificationStatus == .authorized
                         ? "하루 최대 4번, 밤 11시부터 아침 8시까지는 보내지 않아요. 혈당이나 음식 내용은 쓰지 않아요."
                         : "기기에서 알림을 허용해야 받을 수 있어요.")
                }

                Section {
                    ForEach(preferences.mealReminders) { reminder in
                        HStack {
                            Toggle(reminder.name, isOn: mealBinding(reminder.meal).isOn)
                                .tint(Color.mintStrong)
                            if reminder.isOn {
                                DatePicker(reminder.name + " 시각", selection: mealTimeBinding(reminder.meal),
                                           displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                            }
                        }
                    }
                    Toggle("확인 안 한 사진 알림", isOn: Binding(
                        get: { preferences.pendingPhotoReminder },
                        set: { preferences.pendingPhotoReminder = $0; Task { await NudgeScheduler.refresh() } }))
                        .tint(Color.mintStrong)
                } header: {
                    Text("끼니 알림")
                } footer: {
                    Text("그 시각 앞뒤 2시간 안에 이미 기록했다면 보내지 않아요. 알림에서 바로 사진 찍기·투여 확인을 열 수 있어요.")
                }

                Section("쉬어가기") {
                    if let rest = store.isResting() ? store.rest : nil {
                        row("\(rest.reason.title) · \(ReportDay.displayString(from: rest.end))까지",
                            "쉬는 동안은 연속일이 줄지 않고 알림도 멈춰요.")
                        Button("다시 시작하기") {
                            store.endRest()
                            Task { await NudgeScheduler.refresh() }
                        }
                    } else {
                        Button { showRest = true } label: {
                            row("쉬어가기", "아프거나 센서가 없는 날은 연속을 멈춰둘 수 있어요.")
                        }
                        .tint(Color.textPrimary)
                    }
                }

                Section("도움말") {
                    NavigationLink("안내 모아보기") { EducationCardsView() }
                        .foregroundStyle(Color.textPrimary)
                    NavigationLink("위젯 안내") { WidgetGuideView() }
                        .foregroundStyle(Color.textPrimary)
                    Button { showHelp = true } label: { row("앱 사용 도움말", "기록하고 돌아보는 방법") }
                        .tint(Color.textPrimary)
                }

                #if DEBUG
                demoSection
                #endif

                Section {
                    Button("로그아웃", role: .destructive) { showSignOutConfirm = true }
                    Button("계정 삭제", role: .destructive) { showDeleteConfirm = true }
                        .disabled(viewModel.isDeleting)
                } footer: {
                    Text("계정을 지우면 모든 기록이 함께 지워지고 되돌릴 수 없어요.")
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(Color.alert).font(.caption1)
                }
            }
            .navigationTitle("설정")
            .task { notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
            .sheet(isPresented: $showGraphUpload) { GraphUploadView() }
            .sheet(isPresented: $showRest) {
                RestSheet { reason, days in
                    store.startRest(reason, days: days)
                    Task { await NudgeScheduler.refresh() }
                }
            }
            .sheet(isPresented: $showHelp) { HelpSheet() }
            .confirmationDialog("로그아웃하시겠어요?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("로그아웃", role: .destructive) { viewModel.signOut() }
            }
            .confirmationDialog("계정을 삭제하시겠어요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("삭제", role: .destructive) { Task { await viewModel.deleteAccount() } }
            } message: {
                Text("지우면 되돌릴 수 없어요.")
            }
        }
    }

    #if DEBUG
    /// 개발 빌드에만 보이는 데모 데이터 버튼(데모 계정 전용, docs: CLAUDE.md "데모")
    private var demoSection: some View {
        Section {
            Button("시나리오 기록 넣기") { runDemo { await DemoScenarioSeed.run().text } }
            Button("시나리오 기록 지우고 다시 넣기") {
                runDemo {
                    let cleared = await DemoScenarioSeed.clear()
                    return cleared + "\n" + (await DemoScenarioSeed.run().text)
                }
            }
            Button("벌집·연속 서버 기준으로 다시 채우기") {
                runDemo { "그래프 있는 \(await DemoDayCloseSync.run())일을 채웠어요." }
            }
            // 실제 기록 날 지키기: 백업한 날은 시나리오가 지우거나 덮지 않고, 시나리오 넣을 때 그대로 되살린다
            DatePicker("실제 기록 날", selection: $backupDay, in: ...Date.now, displayedComponents: .date)
            Button("이 날 실제 기록 백업하기") {
                runDemo { await DemoDayBackup.backup(day: backupDay) }
            }
            Button("백업한 날 기록 되살리기") {
                runDemo { await DemoDayBackup.restoreAll() }
            }
            if demoRunning { ProgressView() }
            if let demoStatus {
                Text(demoStatus).font(.caption1).foregroundStyle(Color.textSecondary).textSelection(.enabled)
            }
        } header: {
            Text("데모 데이터 (개발용)")
        } footer: {
            Text("데모 계정에서만 쓰세요. 시나리오는 그래프 곡선에 맞춘 식사·처치·인슐린 기록이고, 이미 기록이 있는 날은 건너뛰어요. 백업한 실제 기록 날(\(DemoDayBackup.protectedDays.sorted().joined(separator: ", ")))은 지우지 않고 그대로 되살려요. 백업은 Mac의 ~/glubee-demo-backup에 저장되고 저장소에는 들어가지 않아요.")
        }
        .disabled(demoRunning)
    }

    private func runDemo(_ work: @escaping @MainActor () async -> String) {
        demoRunning = true
        demoStatus = nil
        Task {
            demoStatus = await work()
            demoRunning = false
        }
    }
    #endif

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body1).foregroundStyle(Color.textPrimary)
            Text(detail).font(.caption1).foregroundStyle(Color.textSecondary)
        }
    }

    private func mealBinding(_ meal: MealReminder.Meal) -> Binding<MealReminder> {
        Binding(
            get: { preferences.mealReminders.first { $0.meal == meal } ?? MealReminder.defaults[0] },
            set: { updated in
                preferences.mealReminders = preferences.mealReminders.map { $0.meal == meal ? updated : $0 }
                Task { await NudgeScheduler.refresh() }
            }
        )
    }

    private func mealTimeBinding(_ meal: MealReminder.Meal) -> Binding<Date> {
        Binding(
            get: {
                let reminder = mealBinding(meal).wrappedValue
                return ReportDay.calendar.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: .now) ?? .now
            },
            set: { date in
                var reminder = mealBinding(meal).wrappedValue
                let parts = ReportDay.calendar.dateComponents([.hour, .minute], from: date)
                reminder.hour = parts.hour ?? reminder.hour
                reminder.minute = parts.minute ?? reminder.minute
                mealBinding(meal).wrappedValue = reminder
            }
        )
    }

    private var dayCloseBinding: Binding<Date> {
        Binding(
            get: {
                let time = preferences.dayCloseTime
                return ReportDay.calendar.date(bySettingHour: time.hour ?? 21, minute: time.minute ?? 0,
                                               second: 0, of: .now) ?? .now
            },
            set: { date in
                preferences.dayCloseTime = ReportDay.calendar.dateComponents([.hour, .minute], from: date)
                WidgetSnapshot.refresh()
                Task { await NudgeScheduler.refresh() }
            }
        )
    }

    /// 처음이면 권한 창, 이미 거절했으면 iOS 설정으로
    private func enableNotifications() async {
        let center = UNUserNotificationCenter.current()
        if notificationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(url)
        }
        notificationStatus = await center.notificationSettings().authorizationStatus
        await NudgeScheduler.refresh()
    }
}

/// 평소 인슐린 목록 고치기. 사용자가 넣은 값 그대로 쓰고, 앱이 정하거나 추천하지 않는다
private struct UsualInsulinEditor: View {
    @State private var preferences = UserPreferences.shared
    @State private var name = ""
    @State private var unitsText = ""
    @State private var editing: UsualInsulin?

    var body: some View {
        List {
            Section {
                ForEach(preferences.usualInsulins) { insulin in
                    Button { editing = insulin } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(insulin.name).font(.body1).foregroundStyle(Color.textPrimary)
                                Text(insulin.units.map { "평소 \($0.formatted(.number.precision(.fractionLength(0...1))))U" }
                                     ?? "단위는 그때그때 입력")
                                    .font(.caption1).foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            Text("고치기").font(.caption1).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("usualInsulin-\(insulin.name)")
                }
                .onDelete { offsets in preferences.usualInsulins.remove(atOffsets: offsets) }
            } footer: {
                Text("눌러서 이름·단위를 고칠 수 있어요. 내가 입력한 값을 투여 확인 화면에 그대로 채워둘 뿐, 글루비가 용량을 정하거나 추천하지 않아요.")
            }

            Section("추가") {
                TextField("제품 이름 (예: 초속효성 인슐린)", text: $name)
                TextField("평소 단위 (선택)", text: $unitsText).keyboardType(.decimalPad)
                Button("추가") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    preferences.usualInsulins.append(
                        UsualInsulin(name: trimmed, units: Double(unitsText.replacingOccurrences(of: ",", with: "."))))
                    name = ""
                    unitsText = ""
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("평소 사용하는 인슐린")
        .toolbar { EditButton() }
        .sheet(item: $editing) { insulin in
            UsualInsulinEditSheet(insulin: insulin) { updated in
                if let index = preferences.usualInsulins.firstIndex(where: { $0.id == updated.id }) {
                    preferences.usualInsulins[index] = updated
                }
            }
        }
    }
}

/// 평소 인슐린 하나 고치기(이름·평소 단위)
private struct UsualInsulinEditSheet: View {
    let insulin: UsualInsulin
    let onSave: (UsualInsulin) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var unitsText: String

    init(insulin: UsualInsulin, onSave: @escaping (UsualInsulin) -> Void) {
        self.insulin = insulin
        self.onSave = onSave
        _name = State(initialValue: insulin.name)
        _unitsText = State(initialValue: insulin.units.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("제품 이름", text: $name)
                    .accessibilityIdentifier("usualInsulinName")
                TextField("평소 단위 (비우면 그때그때 입력)", text: $unitsText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("usualInsulinUnits")
            }
            .navigationTitle("평소 인슐린 고치기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        var updated = insulin
                        updated.name = name.trimmingCharacters(in: .whitespaces)
                        updated.units = Double(unitsText.replacingOccurrences(of: ",", with: "."))
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("usualInsulinSave")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// 앱 사용 도움말
private struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                SheetHeader(title: "앱 사용 도움말", onClose: { dismiss() })
                HowToCard()
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("위젯").font(.headline2)
                    Text("홈 화면 빈 곳을 길게 누르고 왼쪽 위 +를 눌러 \"글루비\"를 추가하면, 한 번에 사진 찍기와 인슐린 기록을 열 수 있어요.")
                        .font(.body2).foregroundStyle(Color.textSecondary)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("연속 완성일과 꿀단지").font(.headline2)
                    Text("하루 마무리를 끝낸 날이 연속으로 쌓여요. 7일마다 꿀단지를 하나 받고, 하루를 놓치면 꿀단지가 대신 칸을 채워 연속을 지켜줘요.")
                        .font(.body2).foregroundStyle(Color.textSecondary)
                }
            }
            .padding(Spacing.gutter)
        }
    }
}

#Preview {
    SettingsView()
}
