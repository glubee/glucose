package com.glucoselog.report;

import java.math.BigDecimal;
import java.util.Arrays;

/** 사용자 기록에서 계산한 사실. 모델이 반환하는 숫자나 문장은 사용하지 않는다. */
public record NarrativeFact(String id, BigDecimal value, String unit, String label) {
    enum Definition {
        COVERAGE("coverage_percent", "%", "그래프에서 읽힌 비율", "혈당 그래프의 %s%%를 읽었어요.", "그래프에서 읽힌 비율은 %s%%예요."),
        READINGS("readings_count", "개", "읽힌 관측값 수", "이미지에서 읽힌 관측값은 %s개예요.", "읽힌 값은 %s개예요."),
        AVERAGE("average_glucose", "mg/dL", "읽힌 값의 평균", "이미지에서 읽힌 값의 평균은 %s mg/dL예요.", "읽힌 값 기준 평균은 %s mg/dL예요."),
        MINIMUM("minimum_glucose", "mg/dL", "읽힌 값의 최저", "이미지에서 읽힌 값의 최저는 %s mg/dL예요.", "읽힌 값 기준 최저는 %s mg/dL예요."),
        MAXIMUM("maximum_glucose", "mg/dL", "읽힌 값의 최고", "이미지에서 읽힌 값의 최고는 %s mg/dL예요.", "읽힌 값 기준 최고는 %s mg/dL예요."),
        INTAKES("intake_records", "건", "섭취 기록 수", "섭취 기록은 %s건이에요.", "섭취 기록 %s건이 있어요."),
        INSULIN("insulin_records", "건", "인슐린 기록 수", "인슐린 기록은 %s건이에요.", "인슐린 기록 %s건이 있어요."),
        DATA_DAYS("days_with_data", "일", "그래프가 있는 날 수", "그래프가 있는 날은 %s일이에요.", "%s일의 그래프가 있어요."),
        SUFFICIENT_DAYS("sufficient_days", "일", "지난 날 중 그래프를 충분히 읽은 날 수", "지난 날 중 그래프를 충분히 읽은 날은 %s일이에요.", "그래프를 충분히 읽은 지난 날은 %s일이에요."),
        LIMITED_DAYS("low_coverage_days", "일", "지난 날 중 그래프를 일부만 읽은 날 수", "지난 날 중 그래프를 일부만 읽은 날은 %s일이에요.", "그래프를 일부만 읽은 지난 날은 %s일이에요."),
        PENDING_DAYS("pending_days", "일", "아직 집계 중인 날 수", "아직 집계 중인 날은 %s일이에요.", "집계가 끝나지 않은 날은 %s일이에요."),
        MISSING_DAYS("missing_days", "일", "지난 날 중 그래프가 없는 날 수", "지난 날 중 그래프가 없는 날은 %s일이에요.", "그래프가 없는 지난 날은 %s일이에요."),
        GROUPS("episode_groups", "건", "섭취 기록 묶음 수", "가까운 시각의 섭취 기록 묶음은 %s건이에요.", "섭취 기록 묶음은 %s건이에요."),
        ABOVE("above_range_after_treatment_count", "건", "처치 기록 뒤 그래프 상단에 닿는 값이 읽힌 묶음 수", "처치 기록 뒤 그래프 상단에 닿는 값이 읽힌 기록 묶음은 %s건이에요.", "읽힌 구간에서 처치 기록 뒤 그래프 상단에 닿는 값이 관찰된 묶음은 %s건이에요.");

        final String id;
        final String unit;
        final String label;
        final String plain;
        final String concise;

        Definition(String id, String unit, String label, String plain, String concise) {
            this.id = id;
            this.unit = unit;
            this.label = label;
            this.plain = plain;
            this.concise = concise;
        }

        NarrativeFact fact(Number value) {
            return new NarrativeFact(id, value == null ? null : new BigDecimal(value.toString()), unit, label);
        }

        static Definition find(String id) {
            return Arrays.stream(values()).filter(item -> item.id.equals(id)).findFirst().orElseThrow();
        }
    }

    String render(String style) {
        Definition definition = Definition.find(id);
        if (value == null) {
            return definition.label + ": 확인할 수 없어요.";
        }
        return ("CONCISE".equals(style) ? definition.concise : definition.plain)
                .formatted(value.stripTrailingZeros().toPlainString());
    }
}
