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
- [ ] baseline iOS units 통과 확인, 기존 -tabs 설정 버튼으로 곡선이 나오지 않는 UI RED 확인.
- [ ] 모드 인터페이스 및 영속/격리 회귀 RED, 최소 구현, UI·단위 검사 GREEN.
- [ ] 전체 iOS units/UI 및 Debug/Release 앱·위젯 빌드, 독립 리뷰 한 번, 필요한 수정 후 로컬 커밋.
