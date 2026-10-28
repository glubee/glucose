-- 흐름 안내(DailyInsightDetector)가 음식 분류 표시를 쓸 수 있게 자주 먹는 음식을 더한다.
-- sugar_grams는 비워 둔다(당류 숫자는 리포트에 쓰지 않음). 이름이 이미 있으면 건너뛴다.
INSERT INTO food_catalog (id, name, category_hint, tags, sugar_grams) VALUES
    (gen_random_uuid(), '치킨', 'MEAL', 'HIGH_FAT', NULL),
    (gen_random_uuid(), '피자', 'MEAL', 'HIGH_CARB,HIGH_FAT', NULL),
    (gen_random_uuid(), '라면', 'MEAL', 'HIGH_CARB,HIGH_FAT', NULL),
    (gen_random_uuid(), '떡볶이', 'MEAL', 'HIGH_CARB', NULL),
    (gen_random_uuid(), '떡', 'SNACK', 'HIGH_CARB', NULL),
    (gen_random_uuid(), '아이스크림', 'SNACK', 'HIGH_FAT', NULL),
    (gen_random_uuid(), '케이크', 'SNACK', 'HIGH_CARB,HIGH_FAT', NULL),
    (gen_random_uuid(), '샐러드', 'MEAL', NULL, NULL),
    (gen_random_uuid(), '닭가슴살', 'MEAL', NULL, NULL)
ON CONFLICT (name) DO NOTHING;
