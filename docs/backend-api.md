# 백엔드 API 규약 (iOS ↔ Spring)

이 문서는 iOS 앱이 맞춰야 할 백엔드 API의 공통 규칙과, 지금까지 구현된 엔드포인트를 정리한다.
ml-service와의 계약은 `docs/ml-service-contract.md`를 본다. 이 문서는 iOS ↔ 백엔드 계약이다.

## 1. 공통 규칙

| 항목 | 규칙 |
|---|---|
| Base URL | 운영: `https://<도메인>`. 로컬: `http://localhost:8080` |
| 버전 | 경로에 `/v1` 포함 |
| 인증 | `Authorization: Bearer <access_token>`. `/actuator/health`, `/v1/auth/**` 제외 전부 필요 |
| 필드명 | 요청·응답 모두 snake_case |
| 시간 | DB 저장은 UTC `timestamptz`. 응답 JSON은 ISO-8601 (`"2026-10-06T08:00:00Z"`) |
| 요청 추적 | `X-Request-Id` 헤더(선택). 보내지 않으면 서버가 생성해 응답 헤더에 그대로 돌려준다 |
| 오류 응답 | `{code, message, request_id}` (아래 3번) |
| 페이지네이션 | cursor 방식 (아래 4번) |

## 2. 인증 헤더

- `/v1/auth/apple`, `/v1/auth/refresh`로 access/refresh 토큰을 받은 뒤, 그 외 모든 요청에 `Authorization: Bearer <access_token>`을 보낸다.
- access 토큰이 없거나 만료·위조됐으면 401 `{code: "UNAUTHORIZED", ...}`.
- access 토큰 만료 시 `/v1/auth/refresh`로 재발급받는다. refresh 토큰도 만료·무효면 다시 로그인한다.

## 3. 오류 응답

```json
{
  "code": "INVALID_REFRESH_TOKEN",
  "message": "refresh 토큰을 찾을 수 없습니다",
  "request_id": "7f3c2a1e-..."
}
```

| HTTP | 의미 |
|---|---|
| 400 | 요청 값 검증 실패 (`VALIDATION_ERROR`) |
| 401 | 인증 실패/토큰 없음·만료·위조 |
| 403 | 본인 소유가 아닌 리소스 접근 |
| 404 | 리소스 없음 |
| 422 | 요청은 올바르지만 처리할 수 없음 (예: ml-service 쪽 `TOO_LITTLE_DATA`, `GRAPH_NOT_RECOGNIZED`) |
| 500 | 서버 오류 (`INTERNAL_ERROR`) |

현재 정의된 `code` 목록은 13번 표를 본다.

## 4. 페이지네이션 (cursor)

목록을 반환하는 모든 엔드포인트는 동일한 모양을 쓴다.

요청: `GET /v1/xxx?cursor=<opaque>&limit=20` (`limit` 기본 20, 최대 100)

응답:
```json
{
  "items": [ ... ],
  "next_cursor": "opaque-string-or-null"
}
```

- `cursor`는 서버가 내려준 값을 그대로 다음 요청에 돌려주는 불투명 문자열이다. 클라이언트가 내용을 해석하지 않는다.
- `next_cursor`가 `null`이면 마지막 페이지다.

## 5. `POST /v1/auth/apple` — Sign in with Apple 로그인

Apple이 발급한 identity token을 검증해 `app_user`를 upsert하고 자체 토큰을 발급한다.

요청:
```json
{ "identity_token": "<Apple identity token>", "nonce": "선택, Apple 요청 시 쓴 값과 동일해야 함" }
```

응답 200:
```json
{
  "access_token": "<JWT>",
  "refresh_token": "<opaque string>",
  "token_type": "Bearer",
  "expires_in": 900
}
```

| 오류 | code | 원인 |
|---|---|---|
| 401 | `INVALID_APPLE_TOKEN` | 서명/발급자/대상/만료/nonce 중 하나라도 불일치 |

## 6. `POST /v1/auth/refresh` — 토큰 재발급

요청:
```json
{ "refresh_token": "<opaque string>" }
```

응답 200: `/v1/auth/apple`과 동일한 모양. **refresh 토큰은 매번 새 값으로 회전**하며, 응답으로 받은 `refresh_token`으로 이전 값을 교체해야 한다.

| 오류 | code | 원인 |
|---|---|---|
| 401 | `INVALID_REFRESH_TOKEN` | 존재하지 않는 토큰 |
| 401 | `EXPIRED_REFRESH_TOKEN` | 만료된 토큰 |
| 401 | `REFRESH_TOKEN_REUSED` | 이미 회전되어 폐기된 토큰이 재사용됨 → **이 사용자의 모든 세션이 즉시 종료됨**. 클라이언트는 재로그인 화면으로 보낸다 |

토큰 수명: access 15분, refresh 30일.

## 7. `DELETE /v1/me` — 계정 삭제

인증된 사용자 본인의 계정과 모든 연관 데이터를 삭제한다. App Store 심사 요건(앱 내 계정 삭제)을 만족한다.

요청: 본문 없음. `Authorization` 헤더만 필요.

응답: `204 No Content`. 이후 해당 access/refresh 토큰은 모두 무효가 된다.

삭제 범위:
- **즉시 (요청 안에서)**: DB의 사용자·기록·사진 정보·인슐린·혈당 데이터 전부(`app_user` cascade), 사진·그래프에 연결된 인식/분석 job 기록.
- **곧바로 비동기로**: R2에 올라간 사진·그래프 파일. 같은 트랜잭션에서 `USER_STORAGE_PURGE` job을 넣고 워커가
  `photos/{userId}/`, `graphs/{userId}/` 경로를 통째로 지운다(업로드만 하고 완료 안 한 파일 포함). 실패하면 재시도한다.
- **남는 것**: 매일 새벽 DB 백업(R2, 30일 보관)에는 삭제 전 데이터가 백업 보관 기간 동안 남는다. 개인정보 처리 안내에 적어야 한다.

## 8. `POST /v1/photos` — 사진 업로드 시작 (B2)

R2(S3 호환) presigned PUT URL을 발급한다. **앱이 이 URL로 R2에 직접 업로드하며, 서버는 바이트를 중계하지 않는다.**

요청:
```json
{ "content_type": "image/jpeg", "context": "MEAL" }
```
- `content_type`: `image/jpeg` 또는 `image/png`만 허용
- `context`: 선택, `MEAL` `SNACK` `HYPO_TREATMENT` `ALCOHOL` 중 하나 (ml-service 계약과 동일)

응답 201:
```json
{ "photo_id": "<uuid>", "upload_url": "<presigned PUT URL>", "object_key": "photos/...", "expires_in": 600 }
```

앱은 `upload_url`로 이미지 바이트를 `PUT`(헤더 `Content-Type`을 요청 시 보낸 값과 동일하게)한 뒤, 아래 완료 통보를 호출한다.

## 9. `POST /v1/photos/{photoId}/complete` — 사진 업로드 완료 통보 (B2)

요청 본문 없음. R2에 실제로 객체가 올라왔는지 서버가 확인한 뒤 완료 처리하고, 음식 인식을 백그라운드 job으로 큐에 넣는다(응답은 ml-service를 기다리지 않고 바로 간다).

응답: `204 No Content`

| 오류 | code | 원인 |
|---|---|---|
| 404 | `PHOTO_NOT_FOUND` | 본인 소유가 아니거나 없는 사진 (존재 여부를 구분해 알려주지 않음) |
| 409 | `PHOTO_NOT_UPLOADED` | R2에 실제 업로드가 안 된 상태에서 완료만 호출함 |

## 9-1. `GET /v1/photos/{photoId}/view` — 기록한 음식 사진 보기 주소

본인 사진이고 업로드가 끝난(`UPLOADED`) 사진만. 아니면 404 `PHOTO_NOT_FOUND`(다른 사람 사진인지 알 수 없게 같은 응답).
응답 200: `{ "url": "<presigned GET URL>", "expires_in": 600 }`. 앱은 만료 전까지만 메모리에 두고 기기에 저장하지 않는다.
주소는 로그에 남기지 않는다.

## 10. `GET /v1/photos/{photoId}/recognition` — 음식 인식 결과 조회 (B4)

업로드 완료 후 큐에 들어간 음식 인식 job의 결과를 조회한다. ml-service 응답(`docs/ml-service-contract.md`)에서 백엔드가 쓰는 필드만 추린 모양이다.

응답 200:
```json
{
  "is_food_photo": true,
  "items": [
    { "name": "초콜릿", "food_group": "간식", "count": 3, "unit": "조각", "category_hint": "FAST_SUGAR", "tags": ["HIGH_FAT"], "confidence": "high" }
  ],
  "likely_consumed_all": true
}
```

`food_group`은 `한식` / `일식` / `중식` / `간식` 또는 `null`인 표시용 대분류다. 과거 인식 결과에 필드가 없으면 `null`로 반환한다. `name`은 음식명 그대로 유지하며 화면에서만 `한식 - 김치찌개`처럼 조합한다. 기존 `category_hint`·개수·당류 계산과 별개이며, intake 저장 필드는 이번 변경에 포함하지 않는다.

이 결과를 사용자가 확인·수정한 뒤 `POST /v1/intakes`로 최종 확정한다 (AI 값은 제안일 뿐, 수정값이 우선).

| 오류 | code | HTTP | 원인 |
|---|---|---|---|
| `PHOTO_NOT_FOUND` | 404 | 본인 소유가 아니거나 없는 사진 |
| `RECOGNITION_NOT_READY` | 409 | 아직 완료 통보 전이거나, job이 아직 대기/처리 중 |
| `RECOGNITION_FAILED` | 422 | ml-service 호출이 재시도를 다 썼는데도 실패함 |

## 11. 기록(intake) CRUD (B4)

식사·간식·저혈당 처치·음주 기록. 사진 없이도(수동 입력) 만들 수 있다.

### `POST /v1/intakes`
```json
{
  "context": "MEAL",
  "occurred_at": "2026-10-01T08:00:00Z",
  "photo_id": "선택, 사진에서 만든 기록이면 전달",
  "items": [
    { "name": "초콜릿", "count": 3, "unit": "조각" },
    { "name": "콜라", "count": 1, "unit": "캔", "category_hint": "DRINK", "tags": [] }
  ]
}
```
- 항목별로 `category_hint`/`tags`를 **보내면 사용자가 직접 정한 값으로 우선 적용**된다 (AI 제안이나 `food_catalog` 매칭보다 우선).
- `category_hint`를 보내지 않으면 `food_catalog`에서 이름으로 찾아 채운다. 둘 다 없으면 분류 없음(`null`)으로 저장된다.
- `sugar_grams`(당류)는 요청으로 보낼 수 없다 — 항상 `food_catalog` 매칭으로 서버가 계산한다.

응답 201: 아래 모양 (목록/상세 공통)
```json
{
  "id": "<uuid>",
  "context": "MEAL",
  "occurred_at": "2026-10-01T08:00:00Z",
  "photo_id": null,
  "items": [
    { "id": "<uuid>", "name": "초콜릿", "count": 3, "unit": "조각", "category_hint": "FAST_SUGAR", "tags": ["HIGH_FAT"], "sugar_grams": 12.0 }
  ],
  "created_at": "...", "updated_at": "..."
}
```

### `GET /v1/intakes` — 목록 (cursor, 최신순)
### `GET /v1/intakes/{id}` — 상세
### `PATCH /v1/intakes/{id}` — 수정 (요청 모양은 생성과 동일. **항목 전체를 교체**한다, 부분 수정 아님)
### `DELETE /v1/intakes/{id}` — 삭제

| 오류 | code | HTTP |
|---|---|---|
| `INTAKE_NOT_FOUND` | 404 | 본인 소유가 아니거나 없는 기록 |

## 12. 인슐린 기록 CRUD (B4)

입력만 저장한다. **용량 조언·판단은 하지 않는다.**

### `POST /v1/insulin-events`
```json
{ "occurred_at": "2026-10-01T08:05:00Z", "units": 6, "kind": "식사" }
```
- `units`는 0보다 커야 한다. `kind`는 자유 텍스트(예: "식사", "기저")

응답 201: `{ "id", "occurred_at", "units", "kind", "created_at", "updated_at" }`

### `GET /v1/insulin-events` — 목록 (cursor, 최신순)
### `GET /v1/insulin-events/{id}` — 상세
### `PATCH /v1/insulin-events/{id}` — 수정
### `DELETE /v1/insulin-events/{id}` — 삭제

| 오류 | code | HTTP |
|---|---|---|
| `INSULIN_EVENT_NOT_FOUND` | 404 | 본인 소유가 아니거나 없는 기록 |

## 13. 오류 코드 목록 (현재까지)

| code | HTTP | 설명 |
|---|---|---|
| `VALIDATION_ERROR` | 400 | 요청 값이 올바르지 않음 |
| `UNAUTHORIZED` | 401 | access 토큰 없음/만료/위조 |
| `INVALID_APPLE_TOKEN` | 401 | Apple identity token 검증 실패 |
| `INVALID_REFRESH_TOKEN` | 401 | refresh 토큰 없음 |
| `EXPIRED_REFRESH_TOKEN` | 401 | refresh 토큰 만료 |
| `REFRESH_TOKEN_REUSED` | 401 | refresh 토큰 재사용 감지 (전체 세션 폐기) |
| `PHOTO_NOT_FOUND` | 404 | 사진 없음/본인 소유 아님 |
| `PHOTO_NOT_UPLOADED` | 409 | R2 업로드 전에 완료 통보함 |
| `RECOGNITION_NOT_READY` | 409 | 음식 인식 job이 아직 대기/처리 중 |
| `RECOGNITION_FAILED` | 422 | 음식 인식이 재시도 후에도 실패 |
| `INTAKE_NOT_FOUND` | 404 | 기록 없음/본인 소유 아님 |
| `INSULIN_EVENT_NOT_FOUND` | 404 | 인슐린 기록 없음/본인 소유 아님 |
| `INTERNAL_ERROR` | 500 | 서버 오류 |
| `GLUCOSE_GRAPH_NOT_FOUND` | 404 | 그래프 업로드 없음/본인 소유 아님 |
| `GLUCOSE_GRAPH_NOT_UPLOADED` | 409 | R2 업로드 전에 완료 통보함 |
| `GRAPH_NOT_READY` | 409 | 그래프 분석 job이 아직 대기/처리 중 |
| `GRAPH_NOT_RECOGNIZED` | 422 | 리브레 일일 그래프로 인식 못 함(격자·눈금·날짜를 못 찾음) — "지원하지 않는 이미지" 안내 |
| `GRAPH_TOO_LITTLE_DATA` | 422 | 그래프는 맞지만 곡선이 하루의 10% 미만 — "데이터가 너무 적어요" 안내 |
| `GRAPH_PARSE_FAILED` | 422 | 그 밖의 그래프 분석 실패(이미지 오류, 재시도 소진 등) |
| `GLUCOSE_DAY_NOT_FOUND` | 404 | 해당 날짜의 혈당 데이터 없음 |

이후 단계(리포트)에서 추가되는 코드는 해당 PR에서 이 표에 이어 추가한다.

## 14. 혈당 그래프 (B5)

리브레 앱에서 공유한 일일 그래프 이미지 1장을 업로드하면 ml-service가 OCR로 그 날의 혈당 시계열을 읽어온다.
업로드 자체는 어떤 날짜인지 모른 채로 시작하고(이미지에서 날짜를 읽는 건 ml-service 몫), 분석이 끝나야 날짜를 알 수 있다.
**같은 사용자의 같은 날짜로 다시 업로드하면 기존 데이터를 덮어쓴다**(재업로드 정책, Dave 확인).

### `POST /v1/glucose-graphs` — 업로드 시작
```json
{ "content_type": "image/jpeg" }
```
응답 201: `{ "upload_id": "<uuid>", "upload_url": "<presigned PUT URL>", "object_key": "graphs/...", "expires_in": 600 }`

### `POST /v1/glucose-graphs/{uploadId}/complete` — 업로드 완료 통보
R2에 실제로 올라왔는지 확인한 뒤 그래프 분석을 백그라운드 job으로 큐에 넣는다(응답은 ml-service를 기다리지 않는다).
응답: `204 No Content`

### `GET /v1/glucose-graphs/{uploadId}` — 분석 상태 조회
분석 중이면 409 `GRAPH_NOT_READY`. 실패했으면 422 — 원인별로 `GRAPH_NOT_RECOGNIZED`(지원하지 않는 이미지),
`GRAPH_TOO_LITTLE_DATA`(데이터 부족), 그 외 `GRAPH_PARSE_FAILED`.
완료되면 200: `{ "date": "2026-10-01", "coverage_ratio": 0.94 }`

### `GET /v1/glucose-readings/{date}` — 날짜별 혈당 시계열 조회
`date`는 `YYYY-MM-DD`. 응답 200:
```json
{
  "date": "2026-10-01",
  "coverage_ratio": 0.94,
  "readings": [
    { "time": "00:00", "value": 120, "flag": "NORMAL" },
    { "time": "00:15", "value": null, "flag": "MISSING" }
  ]
}
```
`value`가 `null`인 구간은 **보간하지 않은 결측**이다. 해당 날짜에 분석 완료된 그래프가 없으면 404 `GLUCOSE_DAY_NOT_FOUND`.

## 15. 에피소드/반동 판정 (B6)

API는 없다. `EpisodeAnalyzer`(순수 함수)만 있고, 리포트(B7)가 실제로 조회할 때 intake/glucose_reading을
가져와서 이 함수에 넘기는 방식. 파라미터(묶는 간격, 분석 창 길이, 저혈당 임계값)는 `application.yml`의 `episode.*`.
결과는 저장하지 않고 매번 다시 계산한다 — 사진/그래프가 나중에 추가로 올라와도 오래된 값이 남지 않는다.

## 16. 리포트 (B7)

숫자는 전부 코드가 계산한다. **문장(AI 요약)은 아직 없다** — ml-service 계약에 리포트 문장 생성
엔드포인트가 없어서, 지금은 숫자/건수만 반환한다(Dave 확인). `education_card`는 조건에 따라 붙는
고정 텍스트고 AI가 생성하지 않는다.

### `GET /v1/reports/daily/{date}` — 일일 리포트
`date`는 `YYYY-MM-DD`(한국 시간 기준 하루). 응답 200:
```json
{
  "date": "2026-10-01",
  "glucose": { "coverage_ratio": 0.94, "average": 142.3, "min": 68, "max": 210, "readings_count": 90, "sufficient": true },
  "episodes": [
    {
      "start_at": "2026-10-01T09:00:00Z",
      "original_context": "SNACK",
      "effective_context": "HYPO_TREATMENT",
      "auto_reclassified": true,
      "window_end_at": "2026-10-01T11:00:00Z",
      "rebound_detected": true,
      "intake_count": 1,
      "foods": ["포도당 캔디 3개"],
      "intakes": [
        { "occurred_at": "2026-10-01T09:00:00Z", "context": "SNACK", "photo_id": "…", "foods": ["포도당 캔디 3개"] }
      ]
    }
  ],
  "insulin_events_count": 1,
  "insulin_events": [ { "occurred_at": "2026-10-01T09:05:00Z", "units": 3, "kind": "처치" } ],
  "education_cards": [ {
    "code": "REBOUND", "trigger": "REBOUND", "title": "...", "body": "...",
    "sources": [{ "name": "미국당뇨병학회(ADA) · 반등 용어", "url": "https://diabetes.org/about-diabetes/common-terms", "kind": "EXTERNAL" }],
    "reviewed_by": "요청자", "reviewed_at": "2026-10-28", "review_type": "REQUESTER"
  } ],
  "rebound_glucose_threshold": 180,
  "summary": [
    "이 날 혈당 그래프의 94%를 읽었어요.",
    "읽힌 값 90개 기준, 평균 142.3, 최저 68, 최고 210 mg/dL예요.",
    "18:00 저혈당 처치 기록이 있어요: 포도당 캔디 3개."
  ],
  "story": [
    "이 날 그래프에서 읽힌 값은 최저 68, 최고 210이었어요.",
    "오후 5시 45분쯤 혈당이 68까지 읽혀 오후 6시에 포도당 캔디 3개를 먹었어요.",
    "그 뒤 15분 만에 92로 올라왔고, 2시간 안에 210까지 읽혔어요."
  ]
}
```
- `glucose`가 `null`이면 그날 분석 완료된 그래프가 없다 — **판단 불가**.
- `glucose.sufficient`는 **기록 충분성**이다: `coverage_ratio >= report.sufficient-coverage-ratio`(기본 0.7)이면 `true`.
  우리 앱의 기록 상태 표시일 뿐 혈당이 좋다/나쁘다는 평가가 아니고, 의학적 데이터 충분성 기준(예: 14일·70%)과도 다르다.
  임계값 0.7은 임시 제품 기준이며 운영 coverage 분포를 보고 조정한다(2026-10-10 결정).
- `story`: **하루 이야기**. 기록과 그래프에서 읽힌 값을 시간순 문장으로(`DailyStoryBuilder`, AI 없음). 앱은 한 문단으로 이어 보여주고 `summary`는 근거로 둔다.
  시간 순서의 변화만 쓰고 원인·조언은 쓰지 않는다(`docs/report-story-and-guidance-plan.md` 결정 1). 빈 구간은 "알 수 없어요"로 쓴다.
- 에피소드의 `intakes`: 묶음 안 섭취 기록 하나하나(정확한 시각, 입력한 상황, 사진 ID — 사진 없이 남겼으면 `null`, 음식 이름). 앱 그래프에 기록 위치와 사진을 찍는 데 쓴다.
- 에피소드의 `foods`: 묶음 안 섭취 기록의 음식 이름(+개수·단위)을 기록 순서대로. 개수가 없으면 이름만. 요약 문장에도 같은 이름을 붙인다.
- 에피소드의 `auto_reclassified`/`rebound_detected`가 `null`이면 "확인해봤더니 아니다"가 아니라
  **그 시점에 쓸 글루코스 데이터가 없어서 판단 자체를 못 했다**는 뜻이다(`false`와 다르다).
- `rebound_detected`: 저혈당 처치 에피소드의 분석 창 안에서 `rebound_glucose_threshold`(기본 180 mg/dL)를
  **넘는** 값이 하나라도 읽혔는지(2026-10-12 Dave 결정). 정확히 180은 해당하지 않는다. 처치가 아닌 에피소드는 항상 `false`.
  앱은 문구에 이 기준값을 그대로 쓴다(숫자를 앱에 따로 두지 않는다).

### 안내 카드와 상시 정보

`GET /v1/education-cards/review`는 JWT 인증 후 승인된 상시 안내 10장을 배열로 반환한다.
일일 `education_cards`와 동일한 모델이며, 상시 안내의 `trigger`는 null이다.
카드의 `code`, `sources`, `reviewed_by`, `reviewed_at`, `review_type`은 추가 필드다.
`review_type=REQUESTER`는 요청자가 문구를 검토했다는 이력이다.
외부 출처는 HTTPS 링크로, `APP_GUIDE` 출처는 앱 내 분석 안내로 표시한다.
일일 조건 7종·노출 순서·그래프 미등록 처리·문구 검토 이력은 [안내 카드 명세](guidance-cards.md)를 따른다.

### `GET /v1/reports/weekly/{date}` — 주간 리포트
`date`는 그 주(월~일, ISO 기준) 안의 임의의 날. 응답 200:
```json
{
  "week_start": "2026-09-28",
  "week_end": "2026-10-04",
  "days_with_data": 5,
  "days_insufficient": 2,
  "average_glucose": 138.2,
  "episodes_count": 12,
  "rebound_count": 2,
  "insulin_events_count": 10,
  "sufficient_days": 4,
  "low_coverage_days": 1,
  "pending_days": 0,
  "summary": [ "이 주는 4일 충분히 읽혔고, 1일은 일부만 읽혔어요. 2일은 올라온 그래프가 없어요." ]
}
```
- `days_with_data`: 그래프가 있는 날 수(오늘 포함). `days_insufficient`: **오늘 이전**인데 그래프가 없는 날 수.
  이전에는 `7 - days_with_data`라 아직 오지 않은 날도 포함됐지만, 이제는 제외한다(지난 주의 값은 변하지 않는다).
- `sufficient_days` / `low_coverage_days`: 오늘 이전 날 중 그래프가 있고 각각 기록 충분(`glucose.sufficient=true`) / 부족인 날 수.
- `pending_days`: 오늘 및 이후 날 수(집계 중). 충분/부족/누락 어디에도 세지 않는다.
- 주간 전체에 대한 충분/부족 라벨은 두지 않는다. 일수만 보여주고, "좋은 날/아쉬운 날" 같은 혈당 평가는 하지 않는다.
- `average_glucose`는 일평균들의 단순 평균이 아니라 **읽힌 값 개수(`readings_count`)로 가중한 평균**이다(일평균은 소수 첫째 자리로 반올림된 값이라 약간의 오차가 있을 수 있다).
같은 데이터로 다시 호출하면 항상 같은 숫자가 나온다(캐시하지 않고 매번 다시 계산. 단 "오늘"이 바뀌면 `pending_days` 등이 달라진다).

### 본인용 `summary` (일일·주간 공통)
`summary`는 서버가 **고정 문장 틀**에 계산된 사실만 채운 문장 목록이다. AI가 쓰지 않는다. 읽힌 비율·값 개수·
기록 건수·분류·관찰 사실(처치 뒤 반동 기준(180 mg/dL)을 넘는 값이 읽혔는지)과 한계만 말하고, 원인 설명·평가·조언·안심 문구·
인슐린 용량은 넣지 않는다(`medical-info-policy.md` 4장). 읽힌 값이 없으면 "없다/확인하지 못했다"고 쓰고 "없었다"고
쓰지 않는다. 클라이언트는 이 문장을 그대로 표시하고 의학 판단을 다시 계산하지 않는다. 문구는 팀 검토 전 초안이며
의료인 검토를 받지 않았다.

### `GET /v1/reports/clinician?from=YYYY-MM-DD&to=YYYY-MM-DD` — 의료인 공유용 리포트
진료 때 의료인과 기록을 함께 볼 수 있게 **사실과 데이터의 한계만** 정리한다. 진단·소견·평가·조언·교육 카드는 없다.
기간은 한국 시간 날짜로 양끝 포함, 최대 31일. `from`이 `to`보다 늦으면 400 `INVALID_PERIOD`, 31일을 넘으면 400 `PERIOD_TOO_LONG`.
```json
{
  "from": "2026-09-28", "to": "2026-10-04",
  "generated_at": "2026-10-10T03:00:00Z",
  "low_reading_threshold": 70,
  "rebound_threshold": 180,
  "totals": {
    "period_days": 7, "days_sufficient": 4, "days_low_coverage": 1, "days_no_graph": 2, "days_in_progress": 0,
    "readings_count": 480, "average": 138.2, "min": 62, "max": 245,
    "low_reading_count": 3, "above_range_count": 5, "below_range_count": 2,
    "episodes_count": 12, "hypo_treatment_episodes_count": 3, "insulin_events_count": 10
  },
  "days": [
    {
      "date": "2026-09-28", "status": "SUFFICIENT", "coverage_ratio": 0.94,
      "readings_count": 90, "missing_count": 6, "average": 142.3, "min": 62, "max": 210,
      "low_reading_count": 1, "above_range_count": 2, "below_range_count": 0,
      "low_readings": [ { "time": "2026-09-28T08:45:00Z", "value": 62, "flag": "NORMAL" } ],
      "episodes": [
        { "start_at": "2026-09-28T09:00:00Z", "entered_context": "SNACK", "effective_context": "HYPO_TREATMENT",
          "auto_reclassified": true, "window_end_at": "2026-09-28T11:00:00Z", "above_rebound_threshold_observed": true, "intake_count": 1 }
      ],
      "insulin_events": [ { "occurred_at": "2026-09-28T09:05:00Z", "units": 3, "kind": "처치" } ]
    }
  ],
  "notes": [ "사용자가 올린 혈당 그래프 이미지에서 읽은 추정값과 …", "…" ],
  "disclaimer": "일반 정보이며 의료 조언이 아닙니다."
}
```
- `day.status`: `SUFFICIENT`(coverage ≥ 설정 기준) / `LOW_COVERAGE` / `NO_GRAPH`(오늘 이전인데 그래프 없음) /
  `IN_PROGRESS`(오늘 및 이후). 읽힌 값이 없으면 `average`/`min`/`max`는 `null`이다(0이 아님).
- **낮은 값 기준**은 새로 만들지 않고 기존 `episode.hypo-glucose-threshold`를 그대로 쓴다(`low_reading_threshold`로 노출).
  `above_range_count`는 그래프 상단에 붙은 값(`ABOVE_RANGE`, 실제로는 그보다 높음)의 개수다. 범위 내 시간(TIR)·변동계수(CV)는
  이미지 추정값 검증 전이라 제공하지 않는다.
- `above_rebound_threshold_observed`: 처치 뒤 관찰 구간에 `rebound_threshold`(기본 180 mg/dL)를 넘는 값이 읽혔는지
  (`null`=읽힌 값이 없어 확인 불가). 기존 `rebound_detected`와 같은 계산이지만 원인을 암시하지 않는 이름을 쓴다.
  `above_range_count`(그래프 상단에 붙은 값의 개수)와는 다른 값이다. `entered_context`는 사용자가 입력한 분류다.
- `notes`와 `disclaimer`는 서버가 고정해서 항상 붙인다(추정값임, 보간하지 않음, 경계 값 의미, 기록 시각의 한계).
  문구는 팀 검토 전 초안이며 의료인 검토를 받지 않았다.

### 일일·주간 근거 기반 요약

- `POST /v1/reports/daily/{date}/narrative`
- `POST /v1/reports/weekly/{date}/narrative`

JWT 인증 후 해당 사용자의 최신 기록을 서버가 다시 집계한다. 요청 본문으로 사실·수치를 받지 않는다.
기존 GET 응답은 즉시 조회할 수 있고 AI는 위 요약 요청에서만 사용한다.

응답의 `source`는 `AI`(모델이 문단 구성과 표현을 선택) 또는 `TEMPLATE`(비활성·호출/검증 실패 시 대체)다.
`paragraphs[].text`는 백엔드가 고정 문장과 저장된 집계값으로 완성하고, `fact_ids`로 근거를 연결한다.
`facts`는 `id`, `value`, `unit`, `label`을 제공한다. 알 수 없는 `value`는 null이다.
`limitations`의 이미지 추정·공백·경계 정보는 항상 포함한다.

AI가 새로운 수치·원인·평가·치료 조언을 생성하는 자유 문장 방식은 사용하지 않는다.
외부 AI에는 리포트 종류와 사실 ID만 보내고 수치·날짜·사용자 ID·사진·메모·결측 여부를 보내지 않는다.
의료인 공유 API는 이 문장화 기능을 호출하지 않는다.
자세한 내부 계약과 검증은 [근거 기반 문장화](report-narration.md)를 참고한다.

### 음식 기록과 혈당 관찰

- `GET /v1/reports/daily/{date}/food-observations`
- `GET /v1/reports/weekly/{date}/food-observations`

등록된 음식 조합·분량·맥락별로 기록 직전 값, 이후 읽힌 최고, 그 차이와 구간 끝 값을 표시한다.
주간에는 같은 조합의 반복 기록을 묶고 비교 조건을 충족한 서로 다른 날의 관찰만 수치 요약에 사용한다.
최근 직전 값이 없거나 관찰이 진행 중이면 이를 표시하고, 다른 섭취가 겹치거나 경계 값이 있으면 주간 수치 비교에서 제외한다.
인슐린 동반 건수와 자료의 한계는 유지하며 음식의 인과 효과·치료 방법·좋고 나쁨은 판정하지 않는다.
기존 일일·주간 응답을 변경하지 않는 별도 API이며 앱은 기본 리포트와 함께 자동 조회한다.
스키마·관찰 창·분모·품질·반복 요약 조건은 [음식 기록 기반 혈당 관찰](food-observations.md)을 따른다.

### 그래프 원본 재분석 및 구버전 결과 처리

- `POST /v1/glucose-graphs/{uploadId}/reprocess`
- `POST /v1/glucose-graphs/by-date/{date}/reprocess`

JWT 사용자 소유 원본만 재분석할 수 있다. 응답은 202 `{"upload_id":"UUID"}`다.
기존 상태 조회 API를 폴링하며, 진행 중에는 409 `GRAPH_NOT_READY`를 받는다.
같은 업로드가 대기/처리 중이면 새 작업을 중복 생성하지 않는다. 원본이 없으면 404 `GRAPH_SOURCE_NOT_FOUND`다.
재분석 성공 전에는 기존 행을 지우지 않으며 교체는 한 트랜잭션으로 수행한다. 실패해도 원본과 기존 행은 보존된다.

그래프 상태 성공 응답에 `parser_version`을 추가한다. 날짜별 시계열에는 `upload_id`, `parser_version`을 추가한다.
1.1.4 미만 또는 버전 없는 기존 결과는 시계열 조회에서 409 `GRAPH_REPROCESS_REQUIRED`로 안내하고,
리포트의 평균/최저/최고, 주간 집계 및 음식 관찰 근거에서도 제외한다.
새 요청에 구버전 ML 응답이 오면 저장하지 않고 503 `GRAPH_PARSER_OUTDATED`를 반환한다.

오류 원인은 날짜(422 `GRAPH_DATE_NOT_RECOGNIZED`), 축(422 `GRAPH_AXES_NOT_RECOGNIZED`),
서버 OCR(503 `GRAPH_OCR_UNAVAILABLE`)로 구분한다. 모든 실패를 잘린 이미지나 원본이 아닌 이미지로 단정하지 않는다.
자세한 재현 및 검증 범위는 [그래프 분석 경로 보완](graph-pipeline-fix.md)을 참고한다.

## 17. 앞으로 추가될 것 (문서 자리만 미리 잡아둠)

- 안내 카드와 별도로 문장화는 계속 개인 기록 사실만 정리한다.
- B8(레이트 리밋, OpenAPI, 로그 점검, 백업 복구 테스트)
