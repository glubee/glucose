# 계정별 데이터 보존 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans. 사용자 승인 5단계, 현재 전용 clone의 새 기능 브랜치에서 직접 구현하고 마지막에 독립 리뷰 한 번을 수행한다.

**Goal:** 같은 계정에서 완료 상태와 업로드된 대기 사진을 복원하며 오프라인·재전송·계정 전환에 자료를 잃거나 섞지 않는다.
**Architecture:** 서버는 사용자 잠금/명령 UUID로 진행 상태를 반영하고 사진 상태를 보존한다. iOS는 계정별 캐시와 영속 변경 큐를 합성하고 세대 검사 후 서버 응답을 적용한다.
**Tech Stack:** Spring Boot 3.5/Java21/PostgreSQL/Flyway, SwiftUI/Observation/iOS17+, JUnit/Testcontainers/XCTest.
**Spec:** docs/superpowers/specs/2026-10-29-data-preservation-design.md

## Global Constraints
- 운영 서버·DB·main·PR78·TestFlight를 변경하지 않는다. API 추가/DB 마이그레이션은 코드와 로컬 검사로 준비한다.
- snake_case 응답, 한국 날짜 경계, 꿀단지 7일/최대2/정오 유예, 의료 판정·용량 추천 변경 없음.
- 소유자 불명 예전 자료는 자동 업로드 금지. 실패/부분 목록/오래된 응답으로 사진을 지우지 않는다.
- 서명 URL·토큰·사진/건강정보 원문은 로그/커밋 금지. 저장 주소는 기존 캐시를 사용하고 계정 전환 시 비운다.

## Review Focus
- 같은 완료/명령/업로드를 응답 유실 후 반복하거나 두 기기가 동시에 처리해도 보상이 중복되거나 다른 변경이 사라지지 않는다.
- 오프라인 큐를 보내는 동안 생긴 변경, 응답 역전, 로그아웃/재로그인의 이전 응답이 올바른 계정에만 반영된다.
- 기존 캐시의 첫 이전·재시도·소유자 불명·확인 후 정리 실패에서 기록/파일이 남고 다른 계정으로 전송되지 않는다.
- 대기 사진의 페이지 실패/반복 cursor/확인·숨김 경쟁에서 자료를 잘못 삭제하거나 되살리지 않는다.
- 계정 삭제의 FK cascade와 iOS 캐시/위젯 정리가 남은 작업을 취소하며, 이전 API 필드를 쓰는 앱도 계속 동작한다.

## Task 1: 서버 완료 상태·멱등 명령
**Files:** backend/.../progress/*, db/migration/V14__progress_sync.sql, test/.../progress/ProgressFlowTest.java, docs/backend-api.md.
**Interfaces:** GET /v1/progress, POST /v1/progress/sync; state/revision/acknowledged_operations.
- [ ] HTTP 회귀 먼저: 404 실패 확인; 두 계정 격리, legacy 보존/충돌, 같은 명령·같은 날·7일 보상, 변경ID 재사용, 원자적 배치, 삭제 cascade.
- [ ] 순수 상태 규칙·사용자 잠금·명령 보관·마이그레이션·계약을 구현하고 단위/HTTP 검사 통과 후 커밋.

## Task 2: 서버 사진 복원·상태
**Files:** photo/*, intake/IntakeService.java, AppUserRepository.java, V15__pending_photo_sync.sql, test/.../photo/PendingPhotoFlowTest.java.
**Interfaces:** 목록/메타데이터/숨김 API와 선택 captured_at/client_id. Intake 저장에서 확인 처리.
- [ ] 소유자·페이지·동일 시각·클라이언트ID 재시도·확인/삭제 후 미재등장·숨김 뒤 늦은 완료 회귀를 먼저 실패 확인.
- [ ] 서버 API/기존 업로드 호환·행 잠금·기존 사진 확인 backfill을 구현하고 기존/신규 검사 통과 후 커밋.

## Task 3: iOS 상태 값·영속 큐·계정 캐시
**Files:** Core/Storage/DayCloseStore.swift, DayCloseState.swift, UserPreferences.swift, Core/Sync/ProgressModels.swift, AccountDataCoordinator.swift, AuthSession.swift, LocalDataEraser.swift; glucoseTests/DataPreservationTests.swift.
**Interfaces:** makeSyncRequest(maxOperations:), applyServer(response:), activateAccount(_:allowLegacy:), 계정 식별/기존 자료 가져오기.
- [ ] 중복 마무리·기록만 저장 업그레이드·큐 재실행·응답 도중 새 변경·계정 교체·기존 캐시 이전/격리 검사를 먼저 실패 확인.
- [ ] 순수 상태 계산과 계정별 보관·명령 큐/확인·재생을 구현한다. 기존 UI 호출 인터페이스를 유지하고 단위 검사 후 커밋.

## Task 4: 사진 동기화·전체 동기화 연결
**Files:** Core/Sync/PhotoSyncService.swift, DataSyncCoordinator.swift, PendingPhotoStore.swift, PhotoUploader.swift, PhotoUploadViewModel.swift, 사진 미리보기/썸네일, RootTabView.swift, GlucoseApp.swift.
**Interfaces:** PhotoSyncServing pendingPage/metadata/update/dismiss; DataSyncCoordinator.refresh()와 상태; 원격 메타데이터 병합.
- [ ] 복원 ID/시각/분류, 파일 없는 원격 사진, 숨김 outbox 실패/재시작, 부분 페이지·계정 변경 응답·확인 처리 회귀를 먼저 실패 확인.
- [ ] 명령 push/pull·metadata 이전·사진 복원·숨김 재시도를 연결하고 로그인/활성화/마무리 이후 갱신한다. 기존 사진 흐름 회귀 통과 후 커밋.

## Task 5: 백업 상태 UI·통합 검증·리뷰
**Files:** Settings/BackupSettingsSection.swift, SettingsView.swift, DEBUG SyncSamples.swift, glucoseUITests/DataPreservationUITests.swift, 계획 검증 절.
- [ ] 합성 자료로 백업 대기/오류/재시도, 소유 불명 기존 자료 가져오기, 원격 사진 확인/취소 UI를 검사한다.
- [ ] 백엔드 전체 검사, iOS 단위/UI 전체 검사와 앱·위젯 빌드, diff·민감정보 확인.
- [ ] 독립 전체 리뷰 한 번, 필요한 회귀 수정/재검증, 구현 선택·한계를 기록하고 로컬 커밋한다. 병합/배포하지 않는다.
