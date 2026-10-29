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
- [x] 테스트 먼저: 두 스트림 시간순/같은 시각 보존, 음식·대응 필터의 다음 페이지, cursor 반복, refresh 응답 세대 차단; 오늘 양끝·다음 날 제외·사진 중복 제거·실패 보존.
- [x] 실패 확인 후 필터별 소스와 페이지 병합, 오늘 경계 조회·정렬 구현.
- [x] 단위 검사 통과 후 커밋.

## Task 2: 변경 ID 전달·새 기록 갱신
**Files:** RecordChanges.swift, FoodRecordFormViewModel.swift, RecognitionResultViewModel.swift, Insulin/InsulinService.swift, InsulinRecordFormViewModel.swift, RecordDetailView.swift, glucoseTests/RecordMutationTests.swift.
**Interfaces:** RecordChanges.publish(_:recordID: UUID? = nil); InsulinServing create/update/delete. TodayTimelineViewModel의 focusID로 오늘에 존재하는 생성 행만 선택.
- [x] 테스트 먼저: 저장 응답 ID 발행, 실패/중복 호출 발행 금지, 음식 확인·인슐린 생성/수정/삭제 갱신, 과거 날짜·이미 처리한 변경 강조 금지.
- [x] 서비스 경계를 주입 가능하게 하고 성공 ID를 전달한다. 기존 화면의 중복 발행을 제거한다.
- [x] 단위 검사 통과 후 커밋.

## Task 3: 홈·기록 탭 연결과 화면 검증
**Files:** HomeView.swift, HomeViewModel.swift, HomeTimelineSection.swift, RecordsView.swift, RecordRow.swift, RootTabView.swift, GlucoseApp.swift, SettingsView.swift, DEBUG TimelineSamples.swift, glucoseUITests/HomeRecordsUITests.swift.
**Interfaces:** RecordsView(showsCloseButton: Bool = true); TimelineEntry의 record/pending destination; ScrollViewReader와 약 2초 강조.
- [x] UI 회귀 먼저: 기록 탭 존재·필터 전환·상세 왕복, 홈 대기 사진 열기·취소, 빈 상태 글 입력, 새 저장 후 해당 행 이동.
- [x] 기존 SwiftUI·행·상세 화면을 연결하고 오늘 날짜/앱 복귀·pending 변경을 갱신한다. 안내 모아보기 설정 링크 추가.
- [x] 기존 전체 XCTest/XCUITest와 앱·위젯 빌드, diff 검사, 시뮬레이터 시각 확인.
- [x] 한 번의 독립 전체 리뷰, 필요한 회귀 수정과 재검증. 로컬 커밋, push/merge 없음.

## 구현 선택과 검증 범위
- 홈은 시간 오름차순, 기록 탭은 날짜/시각 내림차순이다. 식사·간식은 음식, 저혈당 처치·음주는 대응 필터에 표시한다.
- DEBUG 실행 인자: `-tabs -timelineSample`, 빈 상태는 `-tabs -timelineEmptySample`. 기록 추가·수정·삭제는 메모리 저장소, 대기 사진은 별도 임시 폴더와 설정을 사용한다. 실제 API·기존 사용자 기록을 수정하지 않는다.
- 예시 기록을 편집해도 고정된 예시 리포트·차트의 분석 숫자는 다시 계산하지 않는다. 실제 실행의 홈·목록·리포트는 기존 RecordChanges를 통해 다시 조회한다.
- 같은 날의 미래 시각도 날짜 범위에 포함한다. 앱 복귀/새로고침 시 날짜를 갱신하며, 자정에 계속 켜둔 상태를 위한 별도 타이머는 추가하지 않았다.
- 현재 API를 유지해 긴 필터 탐색은 오래 걸릴 수 있다. 반복 cursor는 잘못된 페이지로 보고 오류를 표시한다. 조회 실패 시 이전 홈 행과 오류·재시도를 함께 보여주므로 재시도 전까지 이전 정보가 남을 수 있다.
- 리포트 조회가 늦으면 새 기록 강조도 늦을 수 있고, 강조 중 시트를 다시 열면 표시가 재시작될 수 있다. 잘못된 ID 강조나 중복 저장으로 이어지는 문제는 발견하지 못했다.
- 실제 인증 API, 실물 iPhone, iOS 17 런타임, 물리 마우스·트랙패드 입력은 실행 검증 범위 밖이다. 시뮬레이터 터치 검사와 구분한다.

## 독립 리뷰와 회귀 처리
- `5de05b1..84cd453`을 새 검토자가 읽기 전용으로 한 번 검토했다. cursor 병합, 응답 세대 차단, 날짜 경계·중복 제거, 변경 ID, 공통 상세 경로에서 Critical/Important 지적은 없었다.
- 지적 1건: 그래프 없는 홈의 점이 원시 목록 대신 분석 묶음·전체 대기 사진을 사용해 기록 건수와 어긋났다. 저장 직후 원시 기록 표시라는 이번 단계의 동작에 영향을 주므로 수정 대상으로 재평가했다.
- 손으로 정한 기록 4개(음식 2·인슐린 1·대기 사진 1), 이미 저장된 사진 중복, 확인 완료 후 정리 대기 사진을 넣은 회귀 검사에서 점 위치·종류 불일치 실패를 확인했다. todayEntries에서 점도 만들도록 고쳐 통과했다.
- 느린 기록 재조회 중 생성 변경을 먼저 소비해 강조가 사라지는 회귀도 실패→통과로 확인했다. 재조회가 끝나기 전에는 강조 변경을 소비하지 않는다.
- 기존 그래프 위 수직 드래그 검사는 빠른 flick이 버튼을 y=794→113→-551로 지나쳐 실패했다. 고정 헤더 아래로 위치를 맞추는 짧은 드래그로 검사 준비를 안정화했다. 실제 그래프 위 수직 드래그의 이동 검증은 유지했다. 앱의 제스처는 변경하지 않았다.

## 검증 결과 (2026-10-29)
- iPhone 17 Pro / iOS 26.5: 단위 86개 + UI 26개, 전체 112개 통과(실패 0). 리뷰의 점 표시 회귀 포함.
- 앱·위젯 Simulator 빌드 성공.
- 이후 시각 확인에서 홈 목록이 상태바 뒤로 비치는 것을 확인해 ScrollView의 표시 경계를 제한했다. 기존 홈 대기 사진 열기·취소와 새 기록 자동 이동·강조 UI 2건을 다시 실행해 모두 통과했고, 앱·위젯 재빌드도 성공했다. 새로운 서식 복제 테스트는 추가하지 않았다.
- 홈·기록 탭 캡처를 확인했고, 시뮬레이터는 `-tabs -timelineSample`의 기록 탭을 열어 두었다.
- 전체 검사 로그: `/private/tmp/glucose-phase4-verified-tests.log`
- 표시 경계 수정 후 검사/빌드 로그: `/private/tmp/glucose-phase4-visual-check.log`, `/private/tmp/glucose-phase4-visual-build.log`
- 미확인 항목과 구현 선택은 위 절에 명시했다. 원격 push/PR/merge는 수행하지 않았다.
