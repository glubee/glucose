# 설정 기기 데모 Implementation Plan
> **For agentic workers:** Use superpowers:executing-plans inline, one fresh whole-branch review at the end.
**Goal:** 로그인 없이 설정 버튼으로 합성 그래프와 기록을 실제로 표시한다.
**Architecture:** DEBUG LocalDemoSession 활성 상태가 기존 예시 저장소 선택과 RootTab 재생성을 제어한다.
**Tech Stack:** SwiftUI/Observation/iOS17+, XCTest.
**Spec:** docs/superpowers/specs/2026-10-29-local-settings-demo-design.md

## Global Constraints
DEBUG 전용, 서버 인증·실제 데이터·위젯 변경 금지. PR78/운영/중단된 5단계 수정 금지. 합성 예시임과 재실행 초기화 표시.

## Review Focus
- 저장된 데모 활성 상태가 실제 계정 데이터나 위젯을 바꾸지 않는다.
- 전환 후 기존 ViewModel이 서버 저장소를 계속 잡고 있지 않는다.
- 종료/앱 재실행/이미 로그인한 계정과의 경계에서 모드가 명확하다.
- 기존 CLI 예시 검사와 Release 컴파일이 유지된다.

## Task 1: 기기 데모 전환과 UI
**Files:** App/LocalDemoSession.swift, TimelineSamples.swift, RootView.swift, RootTabView.swift; Reports/ReportSamples.swift; Settings/SettingsView.swift; Auth/LoginView.swift, Onboarding/OnboardingView.swift; Tests/LocalDemoSessionTests.swift, UITests/LocalDemoSettingsUITests.swift.
**Interfaces:** LocalDemoSession.shared.isActive/generation/activate(reset:)/deactivate(); RecordDataSource는 기존 선택 인터페이스 유지.
- [x] baseline iOS units 통과 확인, 기존 -tabs 설정 버튼으로 곡선이 나오지 않는 UI RED 확인.
- [x] 모드 인터페이스 및 영속/격리 회귀 RED, 최소 구현, UI·단위 검사 GREEN.
- [x] 전체 iOS units/UI 및 Debug/Release 앱·위젯 빌드, 독립 리뷰 한 번, 필요한 수정 후 로컬 커밋.


## 구현 선택과 리뷰 기록
- 기기 데모 여부만 보존한다. 예시 저장소는 실제 계정과 분리하며 편집 내용은 재실행 시 초기화한다.
- 기기 데모의 API 요청과 위젯·알림 쓰기를 차단한다. 사진·그래프의 서버 업로드는 이 모드에서 사용할 수 없다.
- 기존 고정 ReportSamples를 사용하므로 예시 기록을 편집해도 리포트를 다시 집계하지 않는다. 실제 서버 집계 검증을 기기 데모 결과로 대신하지 않는다.
- 독립 리뷰 1회에서 Important 3건을 확인했다. 직접 -settings/-login 진입 전환, 비동기 서버 데모의 세션·모드 검사, 일일·주간 완료 상태의 데모 저장소 연결을 수정했다. 각각 기존 실패를 재현하는 회귀를 추가했다. Minor 없음.
- 서버 데모 작업은 실행 중 인증 토큰이나 모드가 바뀌면 보수적으로 중단한다. 정상 토큰 갱신 때도 다시 실행해야 할 수 있다.
- 실제 기기·실제 데모 계정 연동 검증과 iOS17 런타임 검증은 수행하지 않았다. 이 변경은 로그인 없는 DEBUG 기기 예시 기능이다.


## 검증 결과
- 기존 단위 검사 기준선 통과. 설정 버튼의 그래프 미표시 및 모드 상태 회귀 RED→GREEN.
- 독립 리뷰의 세 경계 문제를 별도 회귀로 실패 재현 후 수정했다. 최종 전체 검사: 단위 90/90, UI 29/29, 합계 119/119 통과 (`/private/tmp/glucose-local-demo-final.log`).
- 첫 전체 실행의 기존 차트 위치 정렬 검사 1건 실패는 분리 실행과 최종 전체 실행에서 변경 없이 통과했다.
- 수동 화면에서 안내 띠와 헤더 겹침을 발견해 별도 행으로 바꿨다. 관련 UI 3/3 재검사 통과 (`/private/tmp/glucose-local-demo-layout.log`).
- 최종 Debug·Release 앱과 위젯 빌드 통과 (`/private/tmp/glucose-local-demo-build-final.log`, `/private/tmp/glucose-local-demo-release-verified.log`).
- 새 버튼으로 실제 시뮬레이터에 진입한 뒤 일반 실행 인자로 재실행해 기기 데모 유지와 그래프 표시, 헤더 겹침 해소를 수동 확인했다.
- XCTest 터치 스크롤은 통과했다. CUA의 마우스 드래그는 시뮬레이터에서 스크롤을 만들지 못했으며 사용자의 물리 마우스/트랙패드 동작은 검증하지 않았다.
- 서버 데모 계정의 데이터 추가·삭제·날짜 이동, 푸시·PR 수정·머지·배포는 하지 않았다. 중단된 5단계는 원래 체크아웃에 보존한다.
