# 홈 타임라인·기록 탭 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans. 기존 단계 계획의 4단계이며 사용자가 즉시 진행을 승인했다. 현재 전용 clone과 기능 브랜치를 유지한다.

**Goal:** 오늘 기록을 홈에서 확인하고 기록 탭의 필터·상세·수정 흐름으로 이어간다.
**Architecture:** RecordsViewModel의 cursor 병합을 필터별로 확장하고 TodayTimelineViewModel이 오늘의 저장 기록과 PendingPhoto를 합친다. 성공한 변경은 RecordChanges에 반환 ID와 함께 발행하며 기존 상세/입력 화면을 공유한다.
**Tech Stack:** SwiftUI, Observation, XCTest/XCUITest, iOS 17+.
**Spec:** docs/superpowers/specs/2026-10-29-home-records-design.md

## Global Constraints
- 서버 변경 없음. today는 ReportDay.calendar 경계. 같은 시각 항목 유지, 결측 혈당/의료 판정 변경 없음.
- 음식 필터=meal/snack, 대응=hypoTreatment/alcohol. 서버 원시 기록만 사용.
- 탭과 시트에서 같은 상세/편집 UI 재사용. 샘플은 실제 API·사용자 저장소와 분리.
- 실제 서버·실물 iPhone·iOS17 런타임·물리 스크롤 검증은 성공으로 간주하지 않는다.

## Review Focus
- 필터 첫 페이지에 해당 기록이 없고 다음 페이지에 있는 경우 누락 없이 로드한다.
- 날짜 경계·미래 기록·같은 시각·확인 완료됐지만 정리 실패한 사진에서 오늘 건수가 틀리거나 중복되지 않는다.
- 필터 변경/새로고침 중 오래된 성공·실패 응답, 빈 페이지·반복 cursor가 이전 상태를 덮거나 무한 로드를 만들지 않는다.
- 입력 성공/실패와 시트/위젯 진입 후 복귀에서 실제 저장 ID만 한 번 강조한다.
- 상세 수정·삭제 후 이전 행이 남지 않고 전체 기록 시트의 닫기/뒤로가기와 탭 복귀가 유지된다.

## Task 1: 기록 조회·필터·오늘 합치기
**Files:** RecordsViewModel.swift, RecordFilter.swift, Home/TodayTimelineViewModel.swift, Core/Models/TimelineEntry.swift, glucoseTests/HomeTimelineTests.swift.
**Interfaces:** load(filter: RecordFilter = .all), loadNextPage(); TodayTimelineViewModel.load(day: Date), entries(photos: [PendingPhoto]) -> [TimelineEntry].
- [ ] 테스트 먼저: 두 스트림 시간순/같은 시각 보존, 음식·대응 필터의 다음 페이지, cursor 반복, refresh 응답 세대 차단; 오늘 양끝·다음 날 제외·사진 중복 제거·실패 보존.
- [ ] 실패 확인 후 필터별 소스와 페이지 병합, 오늘 경계 조회·정렬 구현.
- [ ] 단위 검사 통과 후 커밋.

## Task 2: 변경 ID 전달·새 기록 갱신
**Files:** RecordChanges.swift, FoodRecordFormViewModel.swift, RecognitionResultViewModel.swift, Insulin/InsulinService.swift, InsulinRecordFormViewModel.swift, RecordDetailView.swift, glucoseTests/RecordMutationTests.swift.
**Interfaces:** RecordChanges.publish(_:recordID: UUID? = nil); InsulinServing create/update/delete. TodayTimelineViewModel의 focusID로 오늘에 존재하는 생성 행만 선택.
- [ ] 테스트 먼저: 저장 응답 ID 발행, 실패/중복 호출 발행 금지, 음식 확인·인슐린 생성/수정/삭제 갱신, 과거 날짜·이미 처리한 변경 강조 금지.
- [ ] 서비스 경계를 주입 가능하게 하고 성공 ID를 전달한다. 기존 화면의 중복 발행을 제거한다.
- [ ] 단위 검사 통과 후 커밋.

## Task 3: 홈·기록 탭 연결과 화면 검증
**Files:** HomeView.swift, HomeViewModel.swift, HomeTimelineSection.swift, RecordsView.swift, RecordRow.swift, RootTabView.swift, GlucoseApp.swift, SettingsView.swift, DEBUG TimelineSamples.swift, glucoseUITests/HomeRecordsUITests.swift.
**Interfaces:** RecordsView(showsCloseButton: Bool = true); TimelineEntry의 record/pending destination; ScrollViewReader와 약 2초 강조.
- [ ] UI 회귀 먼저: 기록 탭 존재·필터 전환·상세 왕복, 홈 대기 사진 열기·취소, 빈 상태 글 입력, 새 저장 후 해당 행 이동.
- [ ] 기존 SwiftUI·행·상세 화면을 연결하고 오늘 날짜/앱 복귀·pending 변경을 갱신한다. 안내 모아보기 설정 링크 추가.
- [ ] 기존 전체 XCTest/XCUITest와 앱·위젯 빌드, diff 검사, 시뮬레이터 시각 확인.
- [ ] 한 번의 독립 전체 리뷰, 필요한 회귀 수정과 재검증. 로컬 커밋, push/merge 없음.
