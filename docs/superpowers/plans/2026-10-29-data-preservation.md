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
- [x] HTTP 회귀 먼저: 404 실패 확인; 두 계정 격리, legacy 보존/충돌, 같은 명령·같은 날·7일 보상, 변경ID 재사용, 원자적 배치, 삭제 cascade.
- [x] 순수 상태 규칙·사용자 잠금·명령 보관·마이그레이션·계약을 구현하고 단위/HTTP 검사 통과 후 커밋.

## Task 2: 서버 사진 복원·상태
**Files:** photo/*, intake/IntakeService.java, AppUserRepository.java, V15__pending_photo_sync.sql, test/.../photo/PendingPhotoFlowTest.java.
**Interfaces:** 목록/메타데이터/숨김 API와 선택 captured_at/client_id. Intake 저장에서 확인 처리.
- [x] 소유자·페이지·동일 시각·클라이언트ID 재시도·확인/삭제 후 미재등장·숨김 뒤 늦은 완료 회귀를 먼저 실패 확인.
- [x] 서버 API/기존 업로드 호환·행 잠금·기존 사진 확인 backfill을 구현하고 기존/신규 검사 통과 후 커밋.

## Task 3: iOS 상태 값·영속 큐·계정 캐시
**Files:** Core/Storage/DayCloseStore.swift, DayCloseState.swift, UserPreferences.swift, Core/Sync/ProgressModels.swift, AccountDataCoordinator.swift, AuthSession.swift, LocalDataEraser.swift; glucoseTests/DataPreservationTests.swift.
**Interfaces:** makeSyncRequest(maxOperations:), applyServer(response:), activateAccount(_:allowLegacy:), 계정 식별/기존 자료 가져오기.
- [x] 중복 마무리·기록만 저장 업그레이드·큐 재실행·응답 도중 새 변경·계정 교체·기존 캐시 이전/격리 검사를 먼저 실패 확인.
- [x] 순수 상태 계산과 계정별 보관·명령 큐/확인·재생을 구현한다. 기존 UI 호출 인터페이스를 유지하고 단위 검사 후 커밋.

## Task 4: 사진 동기화·전체 동기화 연결
**Files:** Core/Sync/PhotoSyncService.swift, DataSyncCoordinator.swift, PendingPhotoStore.swift, PhotoUploader.swift, PhotoUploadViewModel.swift, 사진 미리보기/썸네일, RootTabView.swift, GlucoseApp.swift.
**Interfaces:** PhotoSyncServing pendingPage/metadata/update/dismiss; DataSyncCoordinator.refresh()와 상태; 원격 메타데이터 병합.
- [x] 복원 ID/시각/분류, 파일 없는 원격 사진, 숨김 outbox 실패/재시작, 부분 페이지·계정 변경 응답·확인 처리 회귀를 먼저 실패 확인.
- [x] 명령 push/pull·metadata 이전·사진 복원·숨김 재시도를 연결하고 로그인/활성화/마무리 이후 갱신한다. 기존 사진 흐름 회귀 통과 후 커밋.

## Task 5: 백업 상태 UI·통합 검증·리뷰
**Files:** Settings/BackupSettingsSection.swift, SettingsView.swift, DEBUG SyncSamples.swift, glucoseUITests/DataPreservationUITests.swift, 계획 검증 절.
- [x] 합성 자료로 백업 대기/오류/재시도, 소유 불명 기존 자료 가져오기, 원격 사진 확인/취소 UI를 검사한다.
- [x] 백엔드 전체 검사, iOS 단위/UI 전체 검사와 앱·위젯 빌드, diff·민감정보 확인.
- [x] 독립 전체 리뷰 한 번, 필요한 회귀 수정/재검증, 구현 선택·한계를 기록하고 로컬 커밋한다. 병합/배포하지 않는다.

## 사용자 검증 환경 — 최신 지시 반영
- 사용자는 Apple 로그인 없이 설정의 기기 데모를 쓰며 구현과 로컬 검증을 계속하도록 승인했다. 서버 계정·운영 자료는 변경하지 않는다.
- 화면 수동 확인은 설정의 로컬 데모로 진행한다. 백업 화면은 설정의 “백업 동작 예시 보기”에서 실제 coordinator와 격리 저장소/합성 서버 응답으로 검사하며 “로컬 검증 예시”임을 명시한다.
- 자동 UI 검사의 `-backupSamples`는 같은 예시 화면을 직접 연다. 합성 자료 성공을 실제 계정의 클라우드 백업 성공으로 표현하지 않는다.
- 실제 로그인·여러 기기·배포 서버·TestFlight 검증은 별도 환경이 필요하며 이 단계에서 완료로 표시하지 않는다.

## 구현 결정과 한계
1. 쉬어가기 충돌은 서버 도착 순서로 반영하고, 기존 자료를 추가로 가져올 때 잔여 꿀단지는 합산하지 않는다. 늦게 도착한 오프라인 의도가 마지막으로 반영될 수 있고 서로 다른 예전 잔액은 합쳐지지 않는다.
2. 소유자 불명 예전 자료는 자동 전송하지 않는다. 최초 업그레이드의 판단을 영속화하며 사용자가 현재 계정으로 가져오기를 선택해야 하므로 일부 업그레이드 사용자는 한 번의 추가 조작이 필요하다.
3. 업로드된 사진은 복원할 수 있지만 아직 기기에만 있는 사진은 앱 삭제 후 복원할 수 없다. 설정 백업 설명에서 이 한계를 알린다.
4. 수동 화면 확인은 설정의 기기 데모를 쓰고 백업 UI는 명시적으로 표시한 합성 응답을 사용한다. 로컬 예시 성공을 실제 클라우드 저장 성공으로 해석할 수 없다.
5. 실제 로그인·배포 서버·여러 실기기·TestFlight는 로컬 구현/검증 승인 범위 밖이다. 실제 계정 연동은 후속 환경 검증이 필요하다.
6. 기기 데모의 일반 콘텐츠/시각 품질은 앞선 전용 리뷰에 맡기고 이 단계에서는 계정·동기화 상호작용을 검토했다. 데모 콘텐츠는 실제 사용자 데이터가 아니다.
7. 변경하지 않은 의료 판정·리포트 계산은 이번 보존 리뷰에서 다시 검증하지 않았다. 중복 기록 영향은 수정했으며 도메인 정확성은 기존 별도 검증을 따른다.

## 독립 리뷰와 회귀 수정
전체 브랜치를 한 번 독립 읽기 전용 리뷰했다. Critical 없음, Important 5건을 실제 영향에 따라 확인 후 한 번의 TDD 수정 단계로 처리했다.
- 최초 업그레이드 소유권을 영속화하여 로그아웃 상태의 예전 자료가 나중 로그인/재실행으로 자동 귀속되지 않게 했다.
- 사진 목록을 기다리는 동안 생긴 완료/숨김 변경은 dirty 상태를 남겨 동기화가 한 번 더 처리한다.
- 사진 ID로 확인을 멱등 처리하여 두 기기와 저장 응답 유실 재시도에서 같은 음식 기록을 반환한다. 삭제된 기록을 재생성하지 않는다.
- 파일 없음과 실제 읽기 거부를 구분한다. POSIX 읽기 권한 000 회귀로 목록·숨김 outbox 덮어쓰기를 재현하고 차단했다.
- 알림 예약을 계정/작업 세대에 묶고 이미 진행 중인 늦은 add도 정리한다. 작업별 고유 ID로 새 계정의 예약은 지우지 않는다.
각 회귀의 실패를 먼저 확인한 뒤 관련 iOS 34개 검사와 백엔드 전체 검사를 통과했다. 정식 배포/실계정 확인을 대신하는 결과는 아니다.

보류한 Minor: 원격 복원 직후 위젯·알림의 파생 표시는 다음 앱 활성화 또는 로컬 변경 때 갱신된다. 홈의 복원 상태는 바로 반영된다.

## 최종 로컬 검증
- iOS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/glucose/glucose.xcodeproj -scheme glucose -destination 'platform=iOS Simulator,id=8D5D16BB-3624-4C02-80B8-3AEA1326E010' -derivedDataPath /private/tmp/glucose-phase5-derived test` → 단위 127개 + UI 34개, 실패 0. 최종 로그 `/private/tmp/glucose-phase5-ios-verified.log`, xcresult `Test-glucose-2026.10.29_22-36-14-+0900.xcresult`.
- 백엔드: Java21에서 `./backend/gradlew -p backend --no-daemon test` → 217개, 실패/오류 0, 제외 2개(ReportNarrationLiveTest, GlucoseGraphFlowTest의 실제 입력/서비스 조건부 검사). 로그 `/private/tmp/glucose-phase5-review-backend-all.log`.
- 앱·위젯: 동일 프로젝트 Release 시뮬레이터 빌드 `CODE_SIGNING_ALLOWED=NO build` 성공. Debug 앱·위젯은 최종 검사에서 함께 빌드했다. 로그 `/private/tmp/glucose-phase5-release-final.log`.
- 기존 그래프 UI 검사 준비 동작의 관성으로 180pt 드래그가 약345pt 이동해 목표 위치를 왕복하던 간헐 실패를 좌표 로그로 확인했다. 준비 동작의 속도/놓기 전 정지만 안정화했으며 실제 차트 위 세로 드래그 검증은 유지했다. 관련 단독 UI 2개와 최종 전체 UI 모두 통과했다.
- 설정의 기기 데모 → 백업 예시 진입을 실제 UI 자동 조작으로 확인했다. 화면 캡처는 작업 시각화 폴더의 `phase5-backup-example.png`에 보관했다. 합성 데이터/서버 미연결 안내와 로컬 검증 성공 문구를 눈으로 확인했다.
- iPhone17Pro/iOS26.5 Simulator에서 검증했다. 실기기·iOS17 런타임·실계정·운영 백엔드·TestFlight는 검증하지 않았다. Simulator의 물리 마우스/트랙패드 스크롤은 별도 확인 대상이며 자동 UI 검사는 터치 제스처 기준이다.
- `git diff --check` 통과, 비밀값/운영 사진·건강정보 원문 로그 추가 없음, 금지 폴더 수정 없음. 구현은 `feat/data-preservation`의 로컬 커밋으로 보관한다. 운영 DB 마이그레이션·푸시·PR 병합·TestFlight 업로드 없음.
