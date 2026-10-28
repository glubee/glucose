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

/** 하루 이야기: 시간순 장면, 읽힌 값만, 원인·조언 표현 없음. */
class DailyStoryBuilderTest {

    private static final ZoneId KST = ZoneId.of("Asia/Seoul");
    private static final LocalDate DAY = LocalDate.of(2026, 10, 27);
    /** ReportSummaryBuilderTest와 같은 금지 표현 + 원인을 말하는 표현 */
    private static final List<String> FORBIDDEN = List.of(
            "위험", "정상", "비정상", "늘리세요", "줄이세요", "끊으세요", "잘했어요", "부족해요", "안심", "괜찮",
            "때문", "원인", "덕분", "탓", "영향", "부족", "과다", "해야");

    private final DailyStoryBuilder builder = new DailyStoryBuilder(new EpisodeProperties(90, 4, 2, 12, 70, 180));

    private static Instant at(int hour, int minute) {
        return DAY.atTime(hour, minute).atZone(KST).toInstant();
    }

    /** 96칸(15분 간격). valueAt(분) → 값, 음수면 빈 칸 */
    private static List<GlucoseSample> day(IntUnaryOperator valueAt) {
        List<GlucoseSample> samples = new ArrayList<>();
        for (int minute = 0; minute < 24 * 60; minute += 15) {
            int value = valueAt.applyAsInt(minute);
            samples.add(new GlucoseSample(DAY.atStartOfDay(KST).plusMinutes(minute).toInstant(),
                    value < 0 ? null : value, value < 0 ? ReadingFlag.MISSING : ReadingFlag.NORMAL));
        }
        return samples;
    }

    private static EpisodeSummary episode(Instant start, PhotoContext context, List<String> foods) {
        return new EpisodeSummary(start, context, context, false, start.plusSeconds(4 * 3600), false, 1, foods);
    }

    private static void assertClean(List<String> lines) {
        for (String line : lines) {
            for (String word : FORBIDDEN) {
                assertThat(line).as("금지 표현 '%s' in %s", word, line).doesNotContain(word);
            }
        }
    }

    @Test
    void 식사_장면은_먹은_것_인슐린_먹기_전_값_가장_높은_값_내려온_값을_시간순으로_쓴다() {
        // 8:00까지 105, 9:45에 168 최고, 11:00쯤 120
        List<GlucoseSample> samples = day(m -> m < 8 * 60 + 15 ? 105
                : m <= 9 * 60 + 45 ? 105 + (m - 8 * 60) * 63 / 105
                : m <= 11 * 60 ? 168 - (m - 9 * 60 - 45) * 48 / 75
                : 120);
        List<String> lines = builder.build(samples,
                List.of(episode(at(8, 10), PhotoContext.MEAL, List.of("현미밥 1공기", "계란말이 1접시"))),
                List.of(new DailyReportResponse.InsulinEventMarker(at(8, 0), new BigDecimal("4.0"), "노보래피드")));

        assertThat(lines.get(0)).isEqualTo("이 날 그래프에서 읽힌 값은 최저 105, 최고 168이었어요.");
        assertThat(lines).contains("오전 8시에 노보래피드 4단위를 기록했고, 오전 8시 10분에 현미밥 1공기, 계란말이 1접시를 먹었어요.");
        assertThat(lines).anyMatch(line -> line.startsWith("먹기 전 105였던 혈당은 1시간 35분 뒤 168로 가장 높았고, ")
                && line.endsWith("120으로 내려왔어요."));
        assertClean(lines);
    }

    @Test
    void 저혈당_대응_장면은_낮은_값_먹은_것_회복_시각과_반등_여부를_쓴다() {
        // 13:30에 61, 13:45부터 회복, 2시간 동안 150 이하
        List<GlucoseSample> samples = day(m -> m == 13 * 60 + 30 ? 61 : m == 13 * 60 + 15 ? 72
                : m >= 13 * 60 + 45 && m <= 16 * 60 ? 95 : 110);
        List<String> lines = builder.build(samples,
                List.of(episode(at(13, 40), PhotoContext.HYPO_TREATMENT, List.of("포도당 캔디 3개", "오렌지 주스 1잔"))),
                List.of());

        assertThat(lines).contains("오후 1시 30분쯤 혈당이 61까지 읽혀 오후 1시 40분에 포도당 캔디 3개, 오렌지 주스 1잔을 먹었어요.");
        assertThat(lines).contains("그 뒤 5분 만에 95로 올라왔고, 2시간 동안 180을 넘는 값은 없었어요.");
        assertThat(lines).noneMatch(line -> line.contains("낮게 읽혔어요")); // 처치 직전 낮은 값은 따로 쓰지 않는다
        assertClean(lines);
    }

    @Test
    void 따로_떨어진_인슐린과_긴_빈_구간과_처치_없는_낮은_값도_시간순으로_쓴다() {
        List<GlucoseSample> samples = day(m -> m >= 18 * 60 && m < 21 * 60 ? -1 : m == 3 * 60 ? 66 : 120);
        List<String> lines = builder.build(samples, List.of(),
                List.of(new DailyReportResponse.InsulinEventMarker(at(22, 0), new BigDecimal("14"), "트레시바")));

        int low = lines.indexOf("오전 3시쯤 혈당이 66까지 낮게 읽혔어요.");
        int gap = lines.indexOf("오후 6시부터 오후 9시까지는 그래프가 비어 있어 이 구간은 알 수 없어요.");
        int insulin = lines.indexOf("오후 10시에 트레시바 14단위를 기록했어요.");
        assertThat(low).isPositive();
        assertThat(gap).isGreaterThan(low);
        assertThat(insulin).isGreaterThan(gap);
        assertClean(lines);
    }

    @Test
    void 그래프가_없으면_기록만_정리하고_값은_쓰지_않는다() {
        List<String> lines = builder.build(List.of(),
                List.of(episode(at(19, 0), PhotoContext.ALCOHOL, List.of("맥주 2캔"))), List.of());

        assertThat(lines).containsExactly("이 날은 혈당 그래프가 없어 남긴 기록만 정리했어요.", "오후 7시에 맥주 2캔을 마셨어요.");
    }

    @Test
    void 받침에_맞춰_조사를_붙인다() {
        assertThat(DailyStoryBuilder.lastSound("120")).isNotNull();
        assertThat(DailyStoryBuilder.lastSound("168")).isEqualTo('ㄹ');
        assertThat(DailyStoryBuilder.lastSound("105")).isNull();
        assertThat(DailyStoryBuilder.lastSound("짜장면 1그릇")).isNotNull();
        assertThat(DailyStoryBuilder.time(at(0, 30))).isEqualTo("밤 12시 30분");
        assertThat(DailyStoryBuilder.time(at(12, 0))).isEqualTo("낮 12시");
    }
}
