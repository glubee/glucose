package com.glucoselog.report;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.function.IntUnaryOperator;

import org.junit.jupiter.api.Test;

import com.glucoselog.episode.EpisodeProperties;
import com.glucoselog.episode.GlucoseSample;
import com.glucoselog.glucose.ReadingFlag;
import com.glucoselog.photo.PhotoContext;

/** 주간 이야기·요일별·시간대별: 읽힌 값과 기록 횟수만, 원인·평가 없음. */
class WeeklyStoryBuilderTest {

    private static final ZoneId KST = ZoneId.of("Asia/Seoul");
    private static final LocalDate MONDAY = LocalDate.of(2026, 10, 19);
    private final WeeklyStoryBuilder builder = new WeeklyStoryBuilder(new EpisodeProperties(90, 4, 2, 12, 70, 180));

    private static List<GlucoseSample> day(LocalDate date, IntUnaryOperator valueAt) {
        List<GlucoseSample> samples = new ArrayList<>();
        for (int minute = 0; minute < 24 * 60; minute += 15) {
            samples.add(new GlucoseSample(date.atStartOfDay(KST).plusMinutes(minute).toInstant(),
                    valueAt.applyAsInt(minute), ReadingFlag.NORMAL));
        }
        return samples;
    }

    private static Instant at(LocalDate date, int hour) {
        return date.atTime(hour, 0).atZone(KST).toInstant();
    }

    private static DailyReportResponse report(LocalDate date, boolean graph, List<EpisodeSummary> episodes) {
        DailyReportResponse.GlucoseSummary glucose = graph
                ? new DailyReportResponse.GlucoseSummary(new BigDecimal("0.95"), new BigDecimal("120.0"), 65, 210, 96, true)
                : null;
        return new DailyReportResponse(date, glucose, episodes, 0, List.of(), List.of(), List.of(), 180);
    }

    private static EpisodeSummary meal(LocalDate date, int hour, String food) {
        return new EpisodeSummary(at(date, hour), PhotoContext.MEAL, PhotoContext.MEAL, false, at(date, hour + 4), false, 1,
                List.of(food));
    }

    @Test
    void 요일별_시간대별_주간_이야기를_만든다() {
        LocalDate tuesday = MONDAY.plusDays(1);
        List<WeeklyStoryBuilder.DayInput> week = new ArrayList<>();
        week.add(new WeeklyStoryBuilder.DayInput(
                report(MONDAY, true, List.of(meal(MONDAY, 13, "짜장면 1그릇"))),
                day(MONDAY, m -> m == 13 * 60 + 30 ? 210 : m < 6 * 60 ? 100 : 140)));
        week.add(new WeeklyStoryBuilder.DayInput(
                report(tuesday, true, List.of(meal(tuesday, 13, "짜장면 1그릇"))),
                day(tuesday, m -> m == 9 * 60 ? 65 : m < 6 * 60 ? 100 : 140)));
        for (int i = 2; i < 7; i++) {
            week.add(new WeeklyStoryBuilder.DayInput(report(MONDAY.plusDays(i), false, List.of()), List.of()));
        }
        WeeklyReportResponse counts = new WeeklyReportResponse(MONDAY, MONDAY.plusDays(6), 2, 5,
                new BigDecimal("132.4"), 2, 0, 0, 2, 0, 0, List.of());

        WeeklyStoryBuilder.Result result = builder.build(week, counts);

        assertThat(result.days()).hasSize(7);
        assertThat(result.days().get(1).lowCount()).isEqualTo(1);
        assertThat(result.days().get(2).average()).isNull();
        assertThat(result.timeBands()).hasSize(4);
        assertThat(result.timeBands().get(0).average()).isEqualByComparingTo("100");
        assertThat(result.story()).contains(
                "이번 주는 2일 그래프가 있었고, 읽힌 값 평균은 132였어요.",
                "가장 높았던 값은 월요일 오후 1시 30분의 210, 가장 낮았던 값은 화요일 오전 9시의 65였어요.",
                "70 미만으로 읽힌 날은 1일(화요일)이었고, 저혈당 대응 기록은 0번이에요.",
                "가장 자주 남긴 음식은 짜장면(2번)이에요.",
                "앞뒤 1시간 안에 인슐린 기록이 없는 식사·간식은 2번이었어요.",
                "5일은 그래프가 없어 이 날의 흐름은 알 수 없어요.");
        assertThat(result.story()).anyMatch(line -> line.startsWith("시간대별로 보면 ") && line.contains("새벽이 100으로 가장 낮았어요."));
        assertThat(String.join(" ", result.story())).doesNotContain("때문", "원인", "목표", "정상", "위험");
    }
}
