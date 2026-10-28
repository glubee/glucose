#!/usr/bin/env bash
# 데모 계정의 기록 날짜를 통째로 옮긴다(데모용, 실제 사용자에게 쓰지 않는다).
# 그래프 날짜는 이미지 위 날짜를 읽어 정해지므로, 지난 그래프를 올리면 "이번 주"가 비어 보인다.
# 한 계정의 그래프(result_date)·음식(intake.occurred_at)·인슐린(insulin_event.occurred_at)을 같은 일수만큼 옮긴다.
# 혈당값(glucose_reading)은 그래프 날짜 기준 시간칸이라 따로 옮기지 않아도 같이 따라간다. 리포트는 요청 때 계산한다.
#
# 사용 (서버에서, cd /opt/glucose):
#   bash demo-shift-dates.sh --list                         최근 가입 계정과 그래프 날짜 범위
#   bash demo-shift-dates.sh <user_id>                      옮길 내용만 보여준다(바꾸지 않음)
#   bash demo-shift-dates.sh <user_id> --to 2026-10-27      마지막 그래프 날짜를 이 날로(기본: 어제, 한국 시간)
#   bash demo-shift-dates.sh <user_id> --apply              실제로 옮긴다(한 트랜잭션)
set -euo pipefail

GLUCOSE_DIR="${GLUCOSE_DIR:-/opt/glucose}"
cd "$GLUCOSE_DIR"
set -a; source .env; set +a
: "${POSTGRES_USER:?.env에 POSTGRES_USER가 없습니다}" "${POSTGRES_DB:?.env에 POSTGRES_DB가 없습니다}"

psql_run() {
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"
}

if [[ "${1:-}" == "--list" ]]; then
  psql_run <<'SQL'
SELECT u.id AS user_id, u.created_at::date AS joined,
       count(g.id) AS graphs, min(g.result_date) AS first_day, max(g.result_date) AS last_day
FROM app_user u LEFT JOIN glucose_graph_upload g ON g.user_id = u.id AND g.result_date IS NOT NULL
GROUP BY u.id ORDER BY u.created_at DESC LIMIT 10;
SQL
  exit 0
fi

USER_ID="${1:-}"
[[ "$USER_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] \
  || { echo "user_id(UUID)를 주세요. 계정 목록: bash demo-shift-dates.sh --list" >&2; exit 1; }
shift

TO=$(TZ=Asia/Seoul date -d yesterday +%F 2>/dev/null || TZ=Asia/Seoul date -v-1d +%F)
APPLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to) TO="$2"; shift 2 ;;
    --apply) APPLY=true; shift ;;
    *) echo "모르는 옵션: $1" >&2; exit 1 ;;
  esac
done
[[ "$TO" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--to는 YYYY-MM-DD" >&2; exit 1; }

DAYS=$(psql_run -tA -v uid="$USER_ID" -v to="$TO" <<'SQL'
SELECT COALESCE(:'to'::date - max(result_date), 0) FROM glucose_graph_upload WHERE user_id = :'uid' AND result_date IS NOT NULL;
SQL
)
DAYS=$(echo "$DAYS" | tr -d '[:space:]')

echo "계정 $USER_ID: 마지막 그래프를 $TO 로 → ${DAYS}일 옮김"
psql_run -v uid="$USER_ID" <<'SQL'
SELECT 'graphs' AS what, count(*) AS rows, min(result_date)::text AS first, max(result_date)::text AS last
  FROM glucose_graph_upload WHERE user_id = :'uid' AND result_date IS NOT NULL
UNION ALL
SELECT 'intakes', count(*), min(occurred_at)::date::text, max(occurred_at)::date::text FROM intake WHERE user_id = :'uid'
UNION ALL
SELECT 'insulin', count(*), min(occurred_at)::date::text, max(occurred_at)::date::text FROM insulin_event WHERE user_id = :'uid';
SQL

if [[ "$DAYS" == "0" ]]; then echo "옮길 것이 없어요."; exit 0; fi
if ! $APPLY; then echo "확인만 했어요. 실제로 옮기려면 --apply 를 붙이세요."; exit 0; fi

psql_run -v uid="$USER_ID" -v days="$DAYS" <<'SQL'
BEGIN;
UPDATE glucose_graph_upload SET result_date = result_date + :'days'::int
  WHERE user_id = :'uid' AND result_date IS NOT NULL;
UPDATE intake SET occurred_at = occurred_at + make_interval(days => :'days'::int) WHERE user_id = :'uid';
UPDATE insulin_event SET occurred_at = occurred_at + make_interval(days => :'days'::int) WHERE user_id = :'uid';
COMMIT;
SQL
echo "옮겼어요. 앱에서 리포트를 새로 열면 바뀐 날짜로 보여요."
