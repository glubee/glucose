# 글루비 안내 카드

2026-10-28 요청자가 이 대화에서 다듬은 문구 17장의 검토 완료와 코드 반영을 확인했다.
검토 이력은 `reviewed_by=요청자`, `reviewed_at=2026-10-28`, `review_type=REQUESTER`로 남긴다.
`REQUESTER`는 의료인 검토가 아니므로 앱은 카드 아래에 검토자를 표시하지 않는다(다른 검토 유형만 "문구 검토: …"로 표시).
의료인 자격·실명·소속이나 학회의 승인을 추정해 기록하지 않는다.

## 저장과 노출

- 원문·제목·출처·검토 이력은 `V12__reviewed_guidance_cards.sql`에 고정한다. 실행 중 AI가 문구를 만들지 않는다.
- 기존 REBOUND/LOW_COVERAGE 행은 갱신하고 일일 5장·상시 10장을 추가한다. 총 17장이다.
- `approved=true`인 카드만 조회한다. 새 행은 기본 미승인이며, 승인하려면 출처와 검토 이력이 필요하다.
- 외부 자료는 `sources[].kind=EXTERNAL` 및 HTTPS URL로 표시한다. 국내 공공 자료(질병관리청 국가건강정보포털, 중앙응급의료센터 E-GEN)를 우선한다.
- 그래프 누락·잘림과 앱의 표시 조건은 `APP_GUIDE`로 구분하고 앱 내 글루비 분석 안내로 펼쳐 보여준다.
  내부 파일 경로를 사용자에게 노출하거나 외부 의학 자료로 표시하지 않는다.
- REVIEW_01~REVIEW_10은 조건 없는 상시 안내다. 일일 카드와 서로 섞지 않는다.

## 일일 조건

서버는 해당 날짜의 한국 시간 기록으로 아래 조건을 독립적으로 선택한다. 같은 조건의 여러 관측은 한 카드로 합친다.
여러 조건이 충족되면 해당 카드들을 모두 반환한다. 순서는 NIGHT_LOW, LOW_READING, HYPO_TREATED,
REBOUND, ALCOHOL, LOW_COVERAGE, GRAPH_EDGE다.

| 코드 | 노출 조건 |
|---|---|
| REBOUND | 기존 에피소드 분석에서 `rebound_detected=true`. 기본 기준은 분석 창 안 180 mg/dL **초과** |
| LOW_COVERAGE | 분석된 그래프의 coverage가 `report.sufficient-coverage-ratio` 미만(현재 0.7). 앱 표시 기준 |
| LOW_READING | `MISSING`이 아니며 값이 있는 70 mg/dL 미만 관측 |
| NIGHT_LOW | 같은 조건의 관측이 한국 시간 00:00 이상, 06:00 미만에 있음 |
| HYPO_TREATED | 사용자가 직접 HYPO_TREATMENT 맥락으로 남긴 섭취 기록이 있음 |
| ALCOHOL | 사용자가 직접 ALCOHOL 맥락으로 남긴 섭취 기록이 있음 |
| GRAPH_EDGE | ABOVE_RANGE 또는 BELOW_RANGE 플래그가 있음 |

- 요청 초안의 REBOUND는 '180 이상'이었으나 기존 앱 판정은 '180 초과'다. 분석 규칙은 유지하고 고정 문구를
  '180 mg/dL을 넘는'으로 일치시켰다. 현재 원문이 180을 명시하므로 설정 기준을 바꿀 때 문구도 함께 검토해야 한다.
- 그래프가 없는 날에는 '일부만 읽혔다'는 카드를 붙이지 않는다. 앱의 그래프 미등록 화면이 이를 안내한다.
- 간식 등을 자동으로 처치로 재분류했다고 해서 사용자가 처치 목적으로 먹었다고 단정하지 않는다.
  HYPO_TREATED와 ALCOHOL은 묶인 에피소드의 대표 맥락 대신 원래 섭취 기록을 조회한다.

## API와 앱

`GET /v1/education-cards/review`는 JWT 인증 후 검토된 상시 안내 10장을 정렬된 JSON 배열로 반환한다.
일일 응답의 `education_cards`도 같은 카드 모델을 쓴다. 기존 trigger/title/body 필드는 유지한다.

```json
{
  "code": "REVIEW_01",
  "trigger": null,
  "title": "그래프의 선과 빈칸 읽기",
  "body": "...",
  "sources": [
    {"name": "미국 NIDDK · 연속혈당측정", "url": "https://www.niddk.nih.gov/health-information/diabetes/overview/managing-diabetes/continuous-glucose-monitoring", "kind": "EXTERNAL"},
    {"name": "글루비 그래프 분석 안내", "url": null, "kind": "APP_GUIDE"}
  ],
  "reviewed_by": "요청자",
  "reviewed_at": "2026-10-28",
  "review_type": "REQUESTER"
}
```

최신 main의 리뷰 탭 '알아두면 좋은 정보'에 카드·출처·검토 이력을 연결한다. 리포트의 기존 '전체 기록' 메뉴는 유지한다.
리뷰 카드는 방문할 때마다 순환하며 다음 안내 버튼으로도 넘길 수 있다. '모든 안내 보기'에서 전체 10장 목록도 제공한다.
조회 실패 시 재시도와 아래로 당겨 새로고침을 제공한다. 일일·상시 카드 모두 원문·출처·문구 검토 이력을 표시한다.
앱은 새 메타데이터가 없는 기존 서버 응답도 계속 읽을 수 있다.
