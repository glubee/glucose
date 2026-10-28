-- 2026-10-28 대화에서 요청자가 문구 검토 및 코드 반영을 확인했다.
-- REQUESTER는 요청자의 문구 검토 이력이다. 의료인 자격이나 학회의 승인을 뜻하지 않는다.
ALTER TABLE education_card
    ADD COLUMN code VARCHAR(64),
    ADD COLUMN placement VARCHAR(16) NOT NULL DEFAULT 'DAILY',
    ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 100,
    ADD COLUMN sources JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN approved BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN reviewed_by VARCHAR(200),
    ADD COLUMN reviewed_at DATE,
    ADD COLUMN review_type VARCHAR(32),
    ALTER COLUMN trigger DROP NOT NULL;

UPDATE education_card SET code = trigger;
ALTER TABLE education_card
    ALTER COLUMN code SET NOT NULL,
    ADD CONSTRAINT education_card_code_unique UNIQUE (code),
    ADD CONSTRAINT education_card_placement_check CHECK (
        (placement = 'DAILY' AND trigger IS NOT NULL) OR (placement = 'REVIEW' AND trigger IS NULL)),
    ADD CONSTRAINT education_card_review_check CHECK (
        NOT approved OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL AND review_type IS NOT NULL
            AND jsonb_typeof(sources) = 'array' AND jsonb_array_length(sources) > 0));

-- 기존 에피소드 판정은 180 "초과"이므로 REBOUND도 "넘는"으로 맞춘다.
-- APP_GUIDE는 앱 내 안내이며 의학적 근거나 학회 목표로 표시하지 않는다.
INSERT INTO education_card (id, code, trigger, placement, sort_order, title, body, sources,
                            approved, reviewed_by, reviewed_at, review_type)
SELECT gen_random_uuid(), v.code, v.trigger, v.placement, v.sort_order, v.title, v.body, v.sources::jsonb,
       true, '요청자', DATE '2026-10-28', 'REQUESTER'
FROM (VALUES
('REBOUND', 'REBOUND', 'DAILY', 40,
 '대응 기록 뒤 높은 수치가 읽혔어요',
 '저혈당 대응 음식 기록 뒤, 그래프에서 180 mg/dL을 넘는 수치가 읽혔어요. 기록만으로 수치가 오른 이유를 알기는 어려워요. 당시 대응과 이후 변화에 관해서는 담당 의료진과 이야기해 보세요.',
 '[{"name":"미국당뇨병학회(ADA) · 반등 용어","url":"https://diabetes.org/about-diabetes/common-terms","kind":"EXTERNAL"},{"name":"글루비 리포트 안내","url":null,"kind":"APP_GUIDE"}]'),
('LOW_COVERAGE', 'LOW_COVERAGE', 'DAILY', 60,
 '오늘 그래프는 일부만 확인됐어요',
 '오늘은 그래프의 일부 구간만 읽을 수 있었어요. 리포트의 수치와 요약에는 읽힌 구간의 정보가 담겨 있어요. 비어 있는 시간에 어떤 변화가 있었는지는 이 리포트에서 확인하기 어려워요.',
 '[{"name":"글루비 그래프 분석 안내","url":null,"kind":"APP_GUIDE"}]'),
('LOW_READING', 'LOW_READING', 'DAILY', 20,
 '70 미만으로 읽힌 수치가 있어요',
 '오늘 그래프에서 70 mg/dL 미만으로 읽힌 수치가 있어요. 그래프의 수치만으로 당시 증상이나 몸 상태까지 알 수는 없어요. 낮게 읽힌 수치의 의미와 대응 방법은 담당 의료진과 이야기해 보세요.',
 '[{"name":"미국 질병통제예방센터(CDC) · 저혈당","url":"https://www.cdc.gov/diabetes/about/low-blood-sugar-hypoglycemia.html","kind":"EXTERNAL"},{"name":"미국 NIDDK · 연속혈당측정","url":"https://www.niddk.nih.gov/health-information/diabetes/overview/managing-diabetes/continuous-glucose-monitoring","kind":"EXTERNAL"}]'),
('NIGHT_LOW', 'NIGHT_LOW', 'DAILY', 10,
 '밤 시간대 낮은 수치가 읽혔어요',
 '밤 0시부터 오전 6시 전 사이에 70 mg/dL 미만으로 읽힌 수치가 있어요. 잠든 동안에는 혈당이 낮아져도 증상을 알아차리지 못하는 경우가 있어요. 밤 시간대의 혈당 변화와 대응 방법은 담당 의료진과 이야기해 보세요.',
 '[{"name":"미국 질병통제예방센터(CDC) · 밤 시간대 저혈당","url":"https://www.cdc.gov/diabetes/about/low-blood-sugar-hypoglycemia.html","kind":"EXTERNAL"}]'),
('HYPO_TREATED', 'HYPO_TREATED', 'DAILY', 30,
 '저혈당 대응 기록이 있어요',
 '저혈당에 대응하기 위해 먹은 음식이 기록되어 있어요. 음식 기록은 당시의 대응 내용을 남긴 것으로, 이후 혈당이 회복되었는지까지 보여주지는 않아요. 당시 증상과 대응 방법에 관해서는 담당 의료진과 이야기해 보세요.',
 '[{"name":"미국당뇨병학회(ADA) · 저혈당","url":"https://diabetes.org/living-with-diabetes/hypoglycemia-low-blood-glucose","kind":"EXTERNAL"}]'),
('ALCOHOL', 'ALCOHOL', 'DAILY', 50,
 '술을 마신 날의 혈당 변화',
 '오늘은 술을 마신 기록이 있어요. 술은 혈당에 영향을 줄 수 있고, 마신 직후뿐 아니라 시간이 지난 뒤 혈당이 낮아지는 경우도 있어요. 음주와 관련된 혈당 변화와 대응 방법은 담당 의료진과 이야기해 보세요.',
 '[{"name":"미국당뇨병학회(ADA) · 술과 당뇨병","url":"https://diabetes.org/health-wellness/alcohol-and-diabetes","kind":"EXTERNAL"}]'),
('GRAPH_EDGE', 'GRAPH_EDGE', 'DAILY', 70,
 '그래프 끝에 닿은 구간이 있어요',
 '그래프의 위나 아래 끝에 선이 닿은 구간이 있어요. 화면 밖으로 이어지는 부분은 보이지 않아, 실제 수치는 화면에 보이는 값보다 더 높거나 낮을 수 있어요. 이 구간에서는 그래프만으로 정확한 수치를 알기 어려워요.',
 '[{"name":"글루비 그래프 분석 안내","url":null,"kind":"APP_GUIDE"}]'),
('REVIEW_01', NULL, 'REVIEW', 10,
 '그래프의 선과 빈칸 읽기',
 '그래프의 가로축은 시간, 세로축은 포도당 수치를 나타내요. 선을 따라가면 시간에 따른 수치의 흐름을 볼 수 있어요. 선이 끊긴 곳은 그 시간의 값을 확인할 수 없는 구간이며, 혈당에 변화가 없었다는 뜻은 아니에요.',
 '[{"name":"미국 NIDDK · 연속혈당측정","url":"https://www.niddk.nih.gov/health-information/diabetes/overview/managing-diabetes/continuous-glucose-monitoring","kind":"EXTERNAL"},{"name":"글루비 그래프 분석 안내","url":null,"kind":"APP_GUIDE"}]'),
('REVIEW_02', NULL, 'REVIEW', 20,
 '센서와 손끝 혈당은 왜 다를까요?',
 '센서는 피부 아래 세포 사이의 액체에서 포도당을 측정해요. 손끝 혈당계는 손끝에서 얻은 혈액으로 측정해요. 측정하는 곳이 달라, 혈당이 빠르게 오르거나 내려갈 때 두 수치에 차이가 생길 수 있어요.',
 '[{"name":"미국 질병통제예방센터(CDC) · 연속혈당측정기","url":"https://www.cdc.gov/diabetes/treatment/continuous-glucose-monitors.html","kind":"EXTERNAL"}]'),
('REVIEW_03', NULL, 'REVIEW', 30,
 '혈당이 낮을 때 느낄 수 있는 변화',
 '혈당이 낮아지면 식은땀, 손 떨림, 두근거림이나 어지러움이 나타날 수 있어요. 평소와 다르게 혼란스럽게 느끼는 경우도 있어요. 증상은 사람마다 다르고, 혈당이 낮아져도 뚜렷한 증상을 느끼지 못할 수 있어요.',
 '[{"name":"미국 질병통제예방센터(CDC) · 저혈당 증상","url":"https://www.cdc.gov/diabetes/about/low-blood-sugar-hypoglycemia.html","kind":"EXTERNAL"}]'),
('REVIEW_04', NULL, 'REVIEW', 40,
 '낮았던 혈당이 다시 높아졌다면?',
 '혈당이 낮아진 뒤 높은 수치로 올라가는 흐름을 ‘반등’이라고 부르기도 해요. 수치의 변화를 설명할 때 쓰는 말이에요. 그래프에 이런 흐름이 보이더라도, 수치가 오른 원인을 바로 알 수 있는 것은 아니에요.',
 '[{"name":"미국당뇨병학회(ADA) · 반등 용어","url":"https://diabetes.org/about-diabetes/common-terms","kind":"EXTERNAL"}]'),
('REVIEW_05', NULL, 'REVIEW', 50,
 '운동의 영향은 끝난 뒤에도 이어져요',
 '몸을 움직이면 활동 중이나 활동이 끝난 뒤 혈당이 낮아질 수 있어요. 운동의 영향이 몇 시간 뒤나 잠든 동안까지 이어지는 경우도 있어요. 변화가 나타나는 시점과 정도는 활동의 종류·강도·시간과 개인의 상황에 따라 달라요.',
 '[{"name":"미국당뇨병학회(ADA) · 운동과 혈당","url":"https://diabetes.org/health-wellness/fitness/blood-glucose-and-exercise","kind":"EXTERNAL"}]'),
('REVIEW_06', NULL, 'REVIEW', 60,
 '술의 영향은 나중에도 나타나요',
 '술을 마신 뒤에는 시간이 지난 후에도 혈당이 낮아질 수 있어요. 졸림, 혼란, 말이 어눌해지는 모습은 술에 취했을 때와 저혈당 때 모두 나타날 수 있어요. 겉으로 보이는 모습만으로 두 상태를 구분하기는 어려워요.',
 '[{"name":"미국당뇨병학회(ADA) · 술과 당뇨병","url":"https://diabetes.org/health-wellness/alcohol-and-diabetes","kind":"EXTERNAL"}]'),
('REVIEW_07', NULL, 'REVIEW', 70,
 '아픈 날에는 혈당도 달라질 수 있어요',
 '감염이나 몸의 스트레스에 반응해 나오는 호르몬은 혈당을 높일 수 있어요. 아픈 동안 먹는 양이나 활동이 달라지는 것도 혈당에 영향을 줄 수 있어요. 아픈 날의 혈당 확인과 치료 방법은 담당 의료진과 이야기해 보세요.',
 '[{"name":"미국 질병통제예방센터(CDC) · 아픈 날의 당뇨병 관리","url":"https://www.cdc.gov/diabetes/living-with/managing-sick-days.html","kind":"EXTERNAL"}]'),
('REVIEW_08', NULL, 'REVIEW', 80,
 '진료 때 기록과 질문을 함께 봐요',
 '날짜와 시간이 있는 혈당 기록에 음식·활동·약물 기록이 더해지면 당시 상황을 살펴보는 데 도움이 돼요. 그때 느낀 증상과 궁금했던 점을 적은 메모도 진료에서 함께 볼 수 있는 자료예요. 치료에 관한 질문은 담당 의료진과 이야기해 보세요.',
 '[{"name":"미국 NIDDK · 혈당 기록과 진료","url":"https://www.niddk.nih.gov/health-information/diabetes/overview/managing-diabetes","kind":"EXTERNAL"}]'),
('REVIEW_09', NULL, 'REVIEW', 90,
 '숫자 옆의 짧은 메모도 도움이 돼요',
 '같은 혈당 수치라도 당시 먹은 음식이나 활동은 다를 수 있어요. 시간과 함께 남긴 짧은 메모에는 숫자만으로 알기 어려운 상황이 담겨요. 이런 기록은 나중에 하루를 돌아보거나 진료에서 당시 상황을 설명하는 데 도움이 돼요.',
 '[{"name":"미국 NIDDK · 혈당 기록","url":"https://www.niddk.nih.gov/health-information/diabetes/overview/managing-diabetes","kind":"EXTERNAL"}]'),
('REVIEW_10', NULL, 'REVIEW', 100,
 '응급 상황에는 바로 119로 연락해요',
 '의식이 없거나 경련이 있거나 숨쉬기 어려우면 즉시 119에 연락해요. 의식이 없거나 안전하게 삼키기 어려운 사람에게는 음식이나 음료를 먹이지 않아요. 앱 확인이나 담당 의료진의 답변을 기다리며 신고를 미루지 않아요.',
 '[{"name":"질병관리청 국가건강정보포털 · 당뇨병 급성 합병증(저혈당)","url":"https://health.kdca.go.kr/healthinfo/biz/health/gnrlzHealthInfo/gnrlzHealthInfo/gnrlzHealthInfoView.do?cntnts_sn=2350","kind":"EXTERNAL"},{"name":"중앙응급의료센터 E-GEN · 응급상황 시 행동원칙","url":"https://www.e-gen.or.kr/egen/first_aid.do","kind":"EXTERNAL"},{"name":"영국 NHS · 저혈당 응급 안내","url":"https://www.nhs.uk/conditions/low-blood-sugar-hypoglycaemia/","kind":"EXTERNAL"}]')
) AS v(code, trigger, placement, sort_order, title, body, sources)
ON CONFLICT (code) DO UPDATE SET
    title = EXCLUDED.title, body = EXCLUDED.body, sources = EXCLUDED.sources,
    sort_order = EXCLUDED.sort_order, approved = EXCLUDED.approved,
    reviewed_by = EXCLUDED.reviewed_by, reviewed_at = EXCLUDED.reviewed_at, review_type = EXCLUDED.review_type;

CREATE INDEX idx_education_card_placement_approved ON education_card (placement, approved, sort_order, code);
