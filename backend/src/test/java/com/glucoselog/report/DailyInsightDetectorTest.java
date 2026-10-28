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

/** 흐름 안내: 그래프 모양별 규칙, 꺼져 있으면 아무것도 안 만든다, 원인 단정·용량 조언 없음. */
class DailyInsightDetectorTest {

    private static final ZoneId KST = ZoneId.of("Asia/Seoul");
    private static final LocalDate DAY = LocalDate.of(2026, 10, 27);
    private static final EpisodeProperties PROPS = new EpisodeProperties(90, 4, 2, 12, 70, 180);
    private static final List<String> FORBIDDEN = List.of("때문", "원인", "탓", "단위를", "늘리", "줄이", "위험", "정상");

    private final DailyInsightDetector detector = new DailyInsightDetector(PROPS, true);

    private static Instant at(LocalDate day, int hour, int minute) {
        return day.atTime(hour, minute).atZone(KST).toInstant();
    }

    private static List<GlucoseSample> day(IntUnaryOperator valueAt) {
        List<GlucoseSample> samples = new ArrayList<>();
        for (int minute = 0; minute < 24 * 60; minute += 15) {
            samples.add(new GlucoseSample(DAY.atStartOfDay(KST).plusMinutes(minute).toInstant(),
                    valueAt.applyAsInt(minute), ReadingFlag.NORMAL));
        }
        return samples;
    }

    private static EpisodeSummary episode(Instant start, PhotoContext context, List<String> foods, List<String> tags) {
        return new EpisodeSummary(start, context, context, false, start.plusSeconds(4 * 3600), false, 1, foods,
                List.of(new EpisodeSummary.IntakeMark(start, context, null, foods, tags)));
    }

    private static void assertClean(List<ReportInsight> insights) {
        for (ReportInsight insight : insights) {
            assertThat(insight.reviewStatus()).isEqualTo("DRAFT");
            assertThat(insight.sources()).isNotEmpty();
            for (String word : FORBIDDEN) {
                assertThat(insight.title() + insight.body()).as("금지 표현 '%s'", word).doesNotContain(word);
            }
        }
    }

    @Test
    void 먹지_않은_새벽에_40_넘게_오르면_새벽_현상_가능성을_안내한다() {
        // 2시 100 → 6시 160, 기록 없음
        List<ReportInsight> insights = detector.detect(DAY,
                day(m -> m < 2 * 60 ? 105 : m <= 6 * 60 ? 100 + (m - 120) / 4 : 140), List.of(), List.of(), List.of());

        assertThat(insights).extracting(ReportInsight::code).containsExactly("NIGHT_FASTING_RISE");
        assertThat(insights.get(0).body()).contains("새벽 현상", "가능성", "의료진과 확인");
        assertClean(insights);
    }

    @Test
    void 새벽에_먹은_기록이_있으면_새벽_현상으로_보지_않는다() {
        List<ReportInsight> insights = detector.detect(DAY,
                day(m -> m < 2 * 60 ? 105 : m <= 6 * 60 ? 100 + (m - 120) / 4 : 140),
                List.of(episode(at(DAY, 2, 30), PhotoContext.SNACK, List.of("라면 1그릇"), List.of("HIGH_CARB"))),
                List.of(), List.of());

        assertThat(insights).extracting(ReportInsight::code).doesNotContain("NIGHT_FASTING_RISE");
    }

    @Test
    void 인슐린_없이_탄수화물_많은_음식_뒤_크게_오르면_알려준다() {
        // 13:20 짜장면, 110 → 15:00 230
        List<ReportInsight> insights = detector.detect(DAY,
                day(m -> m < 13 * 60 + 15 ? 110 : m <= 15 * 60 ? 110 + (m - 795) * 120 / 105 : 150),
                List.of(episode(at(DAY, 13, 20), PhotoContext.MEAL, List.of("짜장면 1그릇"), List.of("HIGH_CARB", "HIGH_FAT"))),
                List.of(), List.of());

        assertThat(insights).extracting(ReportInsight::code).contains("BIG_RISE_NO_INSULIN");
        ReportInsight insight = insights.stream().filter(i -> i.code().equals("BIG_RISE_NO_INSULIN")).findFirst().orElseThrow();
        assertThat(insight.body()).contains("짜장면 1그릇처럼 탄수화물이 많거나", "기록을 빠뜨렸다면");
        assertClean(insights);
    }

    @Test
    void 인슐린을_기록했으면_인슐린_없음_안내는_없다() {
        List<ReportInsight> insights = detector.detect(DAY,
                day(m -> m < 13 * 60 + 15 ? 110 : m <= 15 * 60 ? 110 + (m - 795) * 120 / 105 : 150),
                List.of(episode(at(DAY, 13, 20), PhotoContext.MEAL, List.of("짜장면 1그릇"), List.of("HIGH_CARB"))),
                List.of(), List.of(new DailyReportResponse.InsulinEventMarker(at(DAY, 13, 10), new BigDecimal("6"), "노보래피드")));

        assertThat(insights).extracting(ReportInsight::code).doesNotContain("BIG_RISE_NO_INSULIN");
    }

    @Test
    void 전날_밤_술_뒤_아침_낮은_값이면_술과_늦은_저혈당을_안내한다() {
        LocalDate yesterday = DAY.minusDays(1);
        List<ReportInsight> insights = detector.detect(DAY, day(m -> m == 9 * 60 + 45 ? 59 : 110), List.of(),
                List.of(episode(at(yesterday, 22, 0), PhotoContext.ALCOHOL, List.of("맥주 2캔"), List.of())), List.of());

        assertThat(insights.get(0).code()).isEqualTo("ALCOHOL_LATE_LOW");
        assertThat(insights.get(0).body()).startsWith("전날 오후 10시에 맥주 2캔 기록이 있고, 오전 9시 45분쯤 59까지");
        assertClean(insights);
    }

    @Test
    void 지방이_많은_음식으로_대응해_천천히_올라오면_빠른_당을_안내한다() {
        // 9:45 59, 9:50 초콜릿, 10:45에야 70 이상
        List<ReportInsight> insights = detector.detect(DAY,
                day(m -> m >= 9 * 60 + 30 && m < 10 * 60 + 45 ? 62 : 110),
                List.of(episode(at(DAY, 9, 50), PhotoContext.HYPO_TREATMENT, List.of("초콜릿 2조각"), List.of("HIGH_FAT"))),
                List.of(), List.of());

        assertThat(insights).extracting(ReportInsight::code).contains("SLOW_TREATMENT_HIGH_FAT");
        ReportInsight insight = insights.stream().filter(i -> i.code().equals("SLOW_TREATMENT_HIGH_FAT")).findFirst().orElseThrow();
        assertThat(insight.body()).contains("초콜릿 2조각을 먹었고", "55분 걸렸어요", "15g", "15분 뒤");
        assertClean(insights);
    }

    @Test
    void 대응_뒤_반동_기준을_넘으면_15_15_원칙을_안내한다() {
        List<ReportInsight> insights = detector.detect(DAY,
                day(m -> m == 13 * 60 + 30 ? 61 : m >= 14 * 60 + 30 && m <= 15 * 60 ? 205 : 110),
                List.of(episode(at(DAY, 13, 40), PhotoContext.HYPO_TREATMENT, List.of("콜라 1캔"), List.of("FAST_SUGAR"))),
                List.of(), List.of());

        assertThat(insights).extracting(ReportInsight::code).contains("TREATMENT_REBOUND");
        assertClean(insights);
    }

    @Test
    void 꺼져_있으면_아무것도_만들지_않는다() {
        DailyInsightDetector off = new DailyInsightDetector(PROPS, false);
        assertThat(off.detect(DAY, day(m -> m < 2 * 60 ? 105 : m <= 6 * 60 ? 100 + (m - 120) / 4 : 140),
                List.of(), List.of(), List.of())).isEmpty();
    }
}
