# 음식 기록 1단계 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement the approved phase task-by-task.

**Goal:** 음식 확인에서 분류를 바꾸고, 사진 없이 기록하고, 기존 음식 기록을 수정·삭제하며 화면 간 변경을 반영한다.

**Architecture:** 기존 SwiftUI 화면과 디자인 시스템을 사용한다. 음식 입력 필드·검증·요청 생성은 공유하고, HTTP 통신은 APIClient를 사용하는 IntakeService에 모은다. 성공한 변경만 관찰 가능한 RecordChanges에 발행해 홈·기록·리포트를 갱신한다.

**Tech Stack:** Swift 5 language mode, SwiftUI, Observation, XCTest, iOS 17+.

**Spec:** /Users/hanliyagi1/Downloads/ux-improvements-2026-10-29.md 1-1·1-2·1-4 및 사용자 승인 1단계(공통 편집, 화면 갱신).

## Global Constraints
- iOS 17+, 기존 디자인 토큰·해요체 유지.
- 서버 API 변경 없음. POST/PATCH /v1/intakes, DELETE/GET /v1/intakes/{id} 사용.
- PATCH는 항목 전체 교체. 사진 연결, category_hint, tags를 보존한다.
- 서버 수치를 앱에서 계산·추천하지 않는다. 키·사용자 데이터는 커밋하지 않는다.
- 저장 실패는 입력을 유지하고 성공으로 처리하지 않는다. 삭제는 UI에서 재확인한다.
- 다음 단계인 사진 삭제·재촬영, 차트 변경, 탭 개편은 포함하지 않는다.

## Review Focus
- 같은 저장을 연속 누르거나 저장 중 삭제할 때 HTTP 요청은 한 번만 실행된다.
- 편집 상세 로딩 실패 후 빈 데이터가 PATCH되지 않는다.
- 실패·취소 후 입력과 확인 대기 사진이 남는다.
- 이전 날짜에서 새 날짜로 옮겨도 홈·일일·주간·목록을 다시 조회한다.
- 알 수 없는 수량/단위와 사용자 음식 분류·태그가 조용히 소실되지 않는다.

## Task 1: 테스트 기반과 입력 검증
**Files:** glucose.xcodeproj/project.pbxproj, shared glucose.xcscheme, glucoseTests/IntakeRecordingTests.swift; Core/Models/{FoodItem,IntakeRecord}.swift; Features/Intake/{EditableFoodItem,FoodRecordDraft}.swift.
- [x] XCTest 타깃·공유 scheme 추가. 기존 음식 확인의 줄바꿈 이름 검증 실패를 확인.
- [x] FoodRecordDraft의 isValid·request, 응답 매핑과 메타데이터 보존 구현.
- [x] 실제 iPhone 시뮬레이터에서 단위 테스트 통과 확인.

## Task 2: 기록 생성·편집·삭제
**Files:** Features/Intake/{IntakeService,FoodRecordFormViewModel,FoodRecordFormView,FoodRecordFields}.swift; Features/Records/RecordDetailView.swift.
**Interfaces:** IntakeServing의 get/create/update/delete/recognize async 메서드. FoodRecordFormViewModel(record:service:changes:)의 load/save/delete, draft, busy/error 상태.
- [x] 사진 없는 여러 음식 생성, 상세 로딩·편집 전체 교체, 삭제, 오류 유지, 중복 요청 방지 테스트를 먼저 작성·실패 확인.
- [x] 공통 필드(분류·이름·개수·단위·시각), 상세 불러오기 및 삭제 확인 UI 구현.
- [x] FoodRecordSheet와 홈에서 글로 남기기 연결.

## Task 3: 사진 확인 분류와 공통 입력
**Files:** Features/Intake/RecognitionResult{View,ViewModel}.swift.
- [x] 인식 결과를 간식으로 바꿔 확정할 때 요청 분류·촬영 시각·사진 ID·항목 보존 테스트 작성·실패 확인.
- [x] 공통 FoodRecordFields 연결, 취소 시 작업 취소, 저장 성공 후에만 기존 onSaved 호출.
- [x] 확인 대기·하루 마무리의 기존 호출도 같은 화면을 사용함을 확인.

## Task 4: 변경 전파와 UI 검증
**Files:** Core/Storage/RecordChanges.swift; App/GlucoseApp.swift; Features/{Home/HomeView,Records/RecordsView,Reports/DailyReportView,Reports/WeeklyReportView}.swift.
- [x] 성공 시에만 revision이 증가하고 실패·중복 시 증가하지 않는 테스트.
- [x] 홈·목록·일일·주간 화면 task(id:) 갱신, 위젯·알림 재계산 연결.
- [x] 전체 iOS 테스트, 앱 빌드, git diff --check 및 시뮬레이터 입력·분류 검증과 삭제 확인 UI 코드 리뷰.
- [x] 최종 독립 코드 리뷰. 실제 서버·계정 미제공에 따른 검증 한계를 명시.

## Verification
xcodebuild -project ios/glucose/glucose.xcodeproj -scheme glucose -destination 'platform=iOS Simulator,id=8D5D16BB-3624-4C02-80B8-3AEA1326E010' -derivedDataPath /private/tmp/glucose-phase1-tests CODE_SIGNING_ALLOWED=NO test

Expected: TEST SUCCEEDED; new tests pass. Existing compiler warnings are recorded separately.

## 결과 (2026-10-29)
- 전체 XCTest 16개 통과, 앱·위젯 시뮬레이터 빌드 통과, git diff --check 통과.
- 메타데이터 보존, nullable 개수·단위 보존, 실패 시 입력 유지, 중복 저장·삭제 방지, 조회 순서 경쟁을 검증했다.
- 코드 리뷰: Critical/Important 없음. 개수의 Java Integer 범위 경계값 지적은 실패 테스트 재현 후 수정하고 전체 테스트를 다시 통과했다.
- 네이티브 시뮬레이터에서 홈 → 음식 기록 → 글로 남기기, 간식 선택, 여러 음식, 단위 편집, 비로그인 저장 실패 시 입력 유지 확인.
- 실제 인증 서버 왕복과 iOS 17 기기 검증은 테스트 계정·서버 정보 및 런타임이 제공되지 않아 남아 있다. 현재 UI 실행은 iOS 26.5 시뮬레이터다.
- 개수·단위는 서버 계약상 선택값이다. 기존 값이 없으면 임의 값을 만들어 넣지 않는다. 이름과 양수 정수 범위를 검증하며 단위의 빈 문자열은 null로 보낸다.
- 요청 실패 중 입력은 유지한다. 사용자가 화면을 닫은 뒤의 임시 입력 복원은 이 단계 범위에 포함하지 않는다.
- 기존 다른 파일의 actor isolation 경고는 유지되며 이번 단계의 빌드·테스트 실패는 없다.
