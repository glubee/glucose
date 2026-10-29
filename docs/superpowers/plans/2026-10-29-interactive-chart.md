# Interactive chart Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans. User authorized the proposed interaction and requested scrolling repair together; continue inline.

**Goal:** 현재 화면에서 이벤트 확인·강조·확대/이동을 제공하고 리포트 드래그 문제를 재현·수정한다.
**Architecture:** ChartEvent/ChartViewport가 데이터·묶음·시간 범위를 계산하고, InteractiveGlucoseChart가 컨트롤·팝업을 소유한다. GlucoseDayChart는 곡선과 실제 좌표·이벤트 버튼을 렌더링한다. 상세 조회는 기존 resolver 재사용.
**Tech Stack:** SwiftUI, Charts, XCTest/XCUITest, Vision(눈금 렌더 회귀).
**Spec:** docs/superpowers/specs/2026-10-29-interactive-chart-design.md

## Global Constraints
- 기존 clone/Xcode 경로 유지, 별도 기능 브랜치. 서버/API/의료 판단 변경 없음.
- 실제 혈당값은 보간해 표시하지 않음. 기존 사진/기록 상세·샘플 저장 차단 유지.
- 전체 작업 검증/리뷰 후 하나의 단계 커밋으로 보관. 원격 push/merge 없음.

## Review Focus
- 같은 시각·다른 종류·동일 사진 기록이 묶여도 각 원래 시각/내용을 보존한다.
- 확대/가로 이동/경계에서 버튼·팝업이 화면 밖이나 서로 겹치지 않는다.
- 팝업/차트 제스처가 부모 화면 세로 스크롤을 막지 않는다.
- 날짜/자료 변경·수정 성공 시 과거 팝업/상세 응답이 남지 않는다.
- 결측 이벤트와 실제 관측값을 혼동하지 않고, 샘플 통계와 곡선이 일치한다.

## Task 1: 스크롤/축 원인과 회귀
- [x] 실제 RootTab 리포트에서 이야기 글 위/여백 드래그 테스트. 실패 원인만 수정; 정상이라면 Simulator 입력 확인.
- [x] 기존 차트 ImageRenderer/Vision 회귀로 시간 글자 정렬 실패를 확인한 후 정렬 수정.
- [x] 단위/UI 선택 실행 → 예상된 회귀만 실패, 수정 후 통과.

## Task 2: 이벤트/뷰포트 모델
- [x] ChartEvent stable ID, Intake/Insulin 실제 자료, screen-space grouping과 균등 배치 테스트 → 구현.
- [x] ChartViewport 범위·핀치 중심·이동·하루 밖 clamp 테스트 → 구현.
- [x] 묶음이 ‘식사 횟수’가 아닌 ‘기록 N건’임을 고정.

## Task 3: 같은 화면 상호작용
- [x] UI 회귀: 팝업 열기/항목 선택/선택 해제, 인슐린 표시, 확대·하루 복귀, 실제 탭 스크롤 → 구현.
- [x] 공통 wrapper, 화면 안 팝업, 사진 보기·기록 상세 명시적 이동. 홈·일일·확대 화면 연결.
- [x] 샘플 통계/설명 일치 테스트 → 수정. 실제 기록 문장/수치 변경 없음.

## Task 4: 최종 검증
- [x] 전체 단위/UI 테스트, 앱·위젯 빌드, diff 확인.
- [x] 독립 전체 리뷰 1회; Important는 회귀 RED→GREEN과 전체 suite로 검증.
- [x] 로컬 커밋/시뮬레이터 최종 표시/실행 한계 기록.

## 작업 결정과 검증 기록
- 기존 clone을 유지하고 feat/ios-interactive-chart 브랜치를 사용했다. Xcode 경로가 유지되며, 작업 중 다른 수정은 없음을 확인했다.
- 사용자의 ‘추가적으로 … 같이 수정’ 요청을 앞서 제시한 인라인 상호작용 안의 실행 승인으로 해석했다. 팝업 수정 기능의 추가 요구는 없어 권장했던 조회/상세 이동 방식을 적용했다.
- 기본 이벤트 선택은 같은 화면의 말풍선이다. 기존 명시적 전체 화면/사진 확대 진입점은 유지했다. 선택지가 일부 더 남는 대신 기존 접근 경로를 보존한다.
- 독립 리뷰에서 확대 시 저녁에서 아침으로 돌아가는 문제가 나왔다. 보던 시간대와 마지막 이벤트 초점을 기억하도록 바꾸고 UI 회귀로 확인한다.
- 리뷰의 예시 관찰 집계 Minor도 이미 포함된 ‘예시 데이터 일치’ 범위이므로 함께 정리했다. 수정 전14/17·OBSERVED, 올바른13/16·LIMITED를 단위 회귀로 확인했다. 서버 분석기는 변경하지 않았다.
- 터치 스크롤은 실제 RootTab에서 이야기 위/차트 위/왕복 모두 통과했다. native 마우스 자동화는 기본 Settings 앱에서도 드래그·휠이 움직이지 않았다. Simulator 앱과 해당 가상 기기를 재시작해도 이 자동화 입력 경로는 복구를 확인하지 못했다. 앱에 근거 없는 스크롤 제스처 우회 코드를 넣지 않는다.
- 실제 사용자 서버 계정/R2 사진 통합, 실물 iPhone/iOS17 런타임 확인은 남아 있다. iOS26.5 Simulator에서 검증한다.

## 말풍선 시각 검증
- 클릭 테스트와 접근성 존재 확인만으로는 화면 위쪽에서 잘린 제목을 잡지 못했다. 실제 화면 OCR 회귀를 추가했다.
- 원인: iOS18.1+에서는 지정한 화살표 방향을 강제한다. 위 공간이 없는데도 arrowEdge.bottom으로 고정해 제목/닫기가 안전 영역 위에 놓였다. [Apple popover API](https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:))와 로컬 SDK 구현으로 확인했다.
- 최종: 안정적인 바깥 뷰에서 실제 마커 좌표에 연결하고, 방향은 시스템이 공간에 맞춰 고른다. 목록·사진·상세는 하나의 작은 스크롤 영역에서 접근한다.
- 실제 캡처 OCR: 수정 전 제목 없음 → 수정 후 제목 있음. 사진 확대/돌아오기까지 통과. 제목 y13.5→325, 닫기 y1.7→313으로 표시 위치가 안전 영역 안으로 이동했다.
- 이전 크기 조정만으로 해결되지 않았던 시도는 최종 검증으로 계산하지 않는다. 시각 보완 중 이전 전체 실행은 중단했고, 최종 버전에서 다시 전체 실행한다.

## 최종 결과 (2026-10-29)
- XCTest73개 + XCUITest21개 =94개 모두 통과, 마지막 전체 xcodebuild test 종료코드0.
- 최종 로그: /private/tmp/glucose-interactive-final-verified.log
- 앱/위젯 generic Simulator 빌드 성공: /private/tmp/glucose-interactive-complete-build.log
- diff whitespace 검사 통과. 새 차트 모듈의 빌드 경고 없음. 기존 다른 모듈의 actor isolation 경고는 별도.
- 팝업 제목은 실제 스크린샷 OCR로 확인. 이전 AX 존재 검사만 통과하던 잘림을 방지한다.
- 양방향 스크롤 검사는 한 번의 관성 flick 거리 대칭을 가정하지 않고, 최대3번의 아래쪽 swipe로 실제 맨 위 복귀를 확인한다.
- 독립 리뷰 Important 확대 초점 및 Minor 예시 관찰 메타데이터 수정 완료. 보류한 코드 리뷰 항목 없음.
- 마우스 자동화 드래그/휠은 기본 Settings에서도 재현됐고 가상 기기 재시작 후에도 복구를 확인하지 못했다. 사용자의 직접 마우스/트랙패드 조작 확인은 남아 있으며 ‘스크롤 전체 복구’로 주장하지 않는다.
- 원격 push/PR/merge 없이 기능 브랜치에 로컬 커밋한다.
