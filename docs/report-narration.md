# 근거 기반 일일·주간 문장화

AI는 수치·단위·사실·의학 지식을 생성하지 않는다. 서버가 계산한 사실 ID를 문단으로 묶고 `PLAIN` 또는 `CONCISE` 표현을 선택한다. 최종 한국어 문장과 숫자, 단위, 결측 설명은 백엔드의 고정 문장 목록에서 렌더링한다. 모델의 자유 문장은 응답 형식에 없다.

## 내부 API 계약

`POST /v1/report/narrate`, JSON, `X-Internal-Token` 필수. 일일과 주간 모두 지원한다.

```json
{
  "kind": "DAILY",
  "facts": [
    {"id":"coverage_percent","value":75},
    {"id":"readings_count","value":72},
    {"id":"average_glucose","value":138.2},
    {"id":"minimum_glucose","value":80},
    {"id":"maximum_glucose","value":210},
    {"id":"intake_records","value":3},
    {"id":"insulin_records","value":2}
  ]
}
```

WEEKLY의 필수 사실은 `days_with_data`, `sufficient_days`, `low_coverage_days`, `pending_days`, `missing_days`, `average_glucose`, `episode_groups`, `insulin_records`, `above_rebound_threshold_after_treatment_count`다. `above_rebound_threshold_after_treatment_count`는 처치 기록 뒤 서버의 `episode.rebound-glucose-threshold`를 넘는 값이 읽힌 묶음 수이며, 그래프 상단 플래그의 개수가 아니다. DAILY는 위 예시의 7개 사실이 필수다. 요청마다 해당 종류의 사실을 정확히 한 번씩 보내며 알 수 없는 값은 null이다. 음수·비유한 수·범위를 벗어난 일수·관측 수 및 소수인 건수는 거부한다. 단위·의미·사용자 지시문을 요청에 넣지 않는다.

```json
{
  "paragraphs": [
    {"fact_ids":["coverage_percent","readings_count"],"style":"PLAIN"},
    {"fact_ids":["average_glucose","minimum_glucose","maximum_glucose"],"style":"CONCISE"},
    {"fact_ids":["intake_records","insulin_records"],"style":"PLAIN"}
  ],
  "model":"configured-report-model",
  "usage":{"input_tokens":0,"output_tokens":0}
}
```

문단은 1~3개다. 모든 요청 사실을 정확히 한 번 참조해야 하며 알 수 없는 ID·중복·누락·다른 style은 거부한다. ML과 백엔드 양쪽에서 검사한다. 백엔드는 응답의 임의 text 필드를 사용하지 않는다. null은 0으로 바꾸지 않고, 확인할 수 없다는 고정 문장으로 표시한다.

OpenAI에는 사실 ID와 리포트 종류만 전송한다. 실제 수치, null 여부, 사용자 ID, 날짜, 사진, 메모는 전송하지 않는다. 응답 저장은 `store=False`, SDK 자동 재시도는 0회이며 총 처리 제한 시간은 10초다. `store=False`는 외부 제공자의 모든 로그·보관이 없다는 뜻이 아니다. [공식 데이터 제어 문서](https://developers.openai.com/api/docs/guides/your-data)를 배포 환경에 맞게 확인한다.

오류는 기존 `{code,message,request_id}`를 따른다. 요청 스키마 오류는 400 `INVALID_REQUEST`, 인증은 401, 검증 실패·모델 설정 오류는 502 `UPSTREAM_AI_ERROR`, 시간 초과는 504 `TIMEOUT`이다. 백엔드는 오류·응답 불일치·비활성 상태에서 동일한 사실 목록을 고정 문장으로 렌더링한다. AI 때문에 기본 리포트를 숨기지 않는다.

## 앱 API

- `POST /v1/reports/daily/{date}/narrative`
- `POST /v1/reports/weekly/{date}/narrative`

기존 JWT 인증을 사용한다. 클라이언트는 수치·사실을 보내지 않으며 서버가 인증된 사용자의 최신 기록을 다시 집계한다. 기존 일일·주간 GET과 의료인 공유 API는 AI를 호출하지 않는다.

응답: `kind`, `source`(`AI`/`TEMPLATE`), `paragraphs`(`text`, `fact_ids`), `facts`(`id`, `value`, `unit`, `label`), `limitations`를 포함한다. 앱에서 문단의 근거와 한계를 확인할 수 있다. 이미지 추정값·읽힌 구간만 계산·경계 표시의 한계는 AI가 생략할 수 없는 고정 문구다.

## 정보의 신뢰 범위

- 확정되는 것은 서버에 저장된 기록과 그 집계다. 이미지 추정값을 센서 원본값이나 정확한 실제 혈당으로 표현하지 않는다.
- 원인·진단·치료·인슐린 용량·일반 목표 비교는 이 문장 목록에 없다.
- 일반 의학 설명과 교육 카드는 이 기능의 입력에 포함하지 않는다. 추후 추가하려면 원문 출처·버전·검토 상태를 관리하는 별도 자료 체계가 필요하다. AI의 자체 지식을 근거로 승인하지 않는다.
- `REPORT_MODEL`은 기존 모델 설정과 별도로 설정할 수 있다. 실제 모델 호출 품질·비용은 합성 데이터로 별도 평가한다.

구조화 응답의 형식 제약은 [OpenAI 공식 Structured Outputs 문서](https://developers.openai.com/api/docs/guides/structured-outputs)를 따른다. 형식 준수만으로 사실성이 보장되지는 않으므로, 사실 ID의 완전성과 중복을 별도로 검사하고 최종 문장을 서버가 렌더링한다.
