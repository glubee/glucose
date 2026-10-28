package com.glucoselog.report;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Duration;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.TextStyle;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.stream.Collectors;

import org.springframework.stereotype.Component;

import com.glucoselog.episode.EpisodeProperties;
import com.glucoselog.episode.GlucoseSample;
import com.glucoselog.photo.PhotoContext;

/**
 * 주간 이야기와 주간 상세(요일별 한 줄, 시간대별 평균, 흐름 안내 모음).
 * 하루 이야기와 같은 원칙: 읽힌 값과 기록만, 시간 순서·횟수만 쓰고 원인·평가·일반 목표 비교는 쓰지 않는다.
 */
@Component
public class WeeklyStoryBuilder {

    private static final ZoneId KST = ZoneId.of("Asia/Seoul");
    private static final int[][] BANDS = {{0, 6}, {6, 12}, {12, 18}, {18, 24}};
    private static final String[] BAND_LABELS = {"새벽", "오전", "오후", "저녁"};

    private final EpisodeProperties properties;

    public WeeklyStoryBuilder(EpisodeProperties properties) {
        this.properties = properties;
    }

    /** 하루치 재료: 일일 리포트 + 그날 그래프 값(없으면 빈 목록) */
    public record DayInput(DailyReportResponse report, List<GlucoseSample> samples) {
        List<GlucoseSample> values() {
            return samples.stream().filter(s -> s.value() != null).toList();
        }
    }

    public record Result(List<String> story, List<WeeklyReportResponse.Day> days,
            List<WeeklyReportResponse.TimeBand> timeBands, List<WeeklyReportResponse.InsightCount> insights) {
    }

    public Result build(List<DayInput> week, WeeklyReportResponse counts) {
        List<WeeklyReportResponse.Day> days = week.stream().map(this::day).toList();
        List<WeeklyReportResponse.TimeBand> bands = bands(week);
        List<WeeklyReportResponse.InsightCount> insights = insightCounts(week);
        return new Result(story(week, counts, days, bands, insights), days, bands, insights);
    }

    private WeeklyReportResponse.Day day(DayInput input) {
        DailyReportResponse report = input.report();
        DailyReportResponse.GlucoseSummary glucose = report.glucose();
        int intakes = report.episodes().stream().mapToInt(EpisodeSummary::intakeCount).sum();
        return new WeeklyReportResponse.Day(report.date(),
                glucose == null ? null : glucose.average(),
                glucose == null ? null : glucose.min(),
                glucose == null ? null : glucose.max(),
                glucose == null ? null : glucose.coverageRatio(),
                intakes, report.insulinEventsCount(), lowRuns(input.values()),
                report.insights().stream().map(ReportInsight::code).toList());
    }

    /** 70 미만이 이어진 구간 수 */
    private int lowRuns(List<GlucoseSample> values) {
        int runs = 0;
        boolean inLow = false;
        for (GlucoseSample sample : values) {
            boolean low = sample.value() < properties.hypoGlucoseThreshold();
            if (low && !inLow) runs++;
            inLow = low;
        }
        return runs;
    }

    private List<WeeklyReportResponse.TimeBand> bands(List<DayInput> week) {
        List<WeeklyReportResponse.TimeBand> bands = new ArrayList<>();
        for (int i = 0; i < BANDS.length; i++) {
            int from = BANDS[i][0];
            int to = BANDS[i][1];
            List<Integer> values = week.stream().flatMap(day -> day.values().stream())
                    .filter(s -> {
                        int hour = s.time().atZone(KST).getHour();
                        return hour >= from && hour < to;
                    })
                    .map(GlucoseSample::value).toList();
            BigDecimal average = values.isEmpty() ? null : BigDecimal.valueOf(
                    values.stream().mapToInt(Integer::intValue).average().orElse(0)).setScale(0, RoundingMode.HALF_UP);
            bands.add(new WeeklyReportResponse.TimeBand(BAND_LABELS[i] + " " + from + "~" + to + "시", from, to, average,
                    values.isEmpty() ? null : values.stream().min(Integer::compare).orElseThrow(),
                    values.isEmpty() ? null : values.stream().max(Integer::compare).orElseThrow(), values.size()));
        }
        return bands;
    }

    private List<WeeklyReportResponse.InsightCount> insightCounts(List<DayInput> week) {
        Map<String, List<ReportInsight>> byCode = new LinkedHashMap<>();
        Map<String, List<LocalDate>> dates = new LinkedHashMap<>();
        for (DayInput day : week) {
            for (ReportInsight insight : day.report().insights()) {
                byCode.computeIfAbsent(insight.code(), k -> new ArrayList<>()).add(insight);
                dates.computeIfAbsent(insight.code(), k -> new ArrayList<>()).add(day.report().date());
            }
        }
        return byCode.entrySet().stream()
                .map(e -> new WeeklyReportResponse.InsightCount(e.getKey(), e.getValue().get(0).title(),
                        dates.get(e.getKey()).size(), dates.get(e.getKey())))
                .sorted(Comparator.comparingInt(WeeklyReportResponse.InsightCount::days).reversed())
                .toList();
    }

    private List<String> story(List<DayInput> week, WeeklyReportResponse counts, List<WeeklyReportResponse.Day> days,
            List<WeeklyReportResponse.TimeBand> bands, List<WeeklyReportResponse.InsightCount> insights) {
        List<String> lines = new ArrayList<>();
        List<GlucoseSample> all = week.stream().flatMap(day -> day.values().stream()).toList();
        if (all.isEmpty()) {
            lines.add("이번 주는 올라온 혈당 그래프가 없어요.");
        } else {
            lines.add("이번 주는 " + counts.daysWithData() + "일 그래프가 있었고, 읽힌 값 평균은 "
                    + counts.averageGlucose().setScale(0, RoundingMode.HALF_UP).toPlainString()
                    + copula(counts.averageGlucose().setScale(0, RoundingMode.HALF_UP).intValue()));
            GlucoseSample top = all.stream().max(Comparator.comparing(GlucoseSample::value)).orElseThrow();
            GlucoseSample bottom = all.stream().min(Comparator.comparing(GlucoseSample::value)).orElseThrow();
            lines.add("가장 높았던 값은 " + weekday(top) + " " + DailyStoryBuilder.time(top.time()) + "의 " + top.value()
                    + ", 가장 낮았던 값은 " + weekday(bottom) + " " + DailyStoryBuilder.time(bottom.time()) + "의 "
                    + bottom.value() + copula(bottom.value()));
            List<WeeklyReportResponse.TimeBand> withValues = bands.stream().filter(b -> b.average() != null).toList();
            if (withValues.size() >= 2) {
                WeeklyReportResponse.TimeBand high = withValues.stream().max(Comparator.comparing(WeeklyReportResponse.TimeBand::average)).orElseThrow();
                WeeklyReportResponse.TimeBand low = withValues.stream().min(Comparator.comparing(WeeklyReportResponse.TimeBand::average)).orElseThrow();
                if (high.average().subtract(low.average()).intValue() >= 15) {
                    String highName = high.label().split(" ")[0];
                    String lowName = low.label().split(" ")[0];
                    lines.add("시간대별로 보면 " + highName + subject(highName) + " 평균 " + high.average().toPlainString()
                            + direction(high.average().intValue()) + " 가장 높고, " + lowName + subject(lowName) + " "
                            + low.average().toPlainString() + direction(low.average().intValue()) + " 가장 낮았어요.");
                }
            }
        }

        List<WeeklyReportResponse.Day> lowDays = days.stream().filter(d -> d.lowCount() > 0).toList();
        if (!lowDays.isEmpty()) {
            long treated = week.stream().flatMap(d -> d.report().episodes().stream())
                    .filter(e -> e.effectiveContext() == PhotoContext.HYPO_TREATMENT).count();
            lines.add("70 미만으로 읽힌 날은 " + lowDays.size() + "일("
                    + lowDays.stream().map(d -> weekday(d.date())).collect(Collectors.joining("·"))
                    + ")이었고, 저혈당 대응 기록은 " + treated + "번이에요.");
        }

        Map<String, Long> foods = week.stream().flatMap(d -> d.report().episodes().stream())
                .filter(e -> e.effectiveContext() == PhotoContext.MEAL || e.effectiveContext() == PhotoContext.SNACK)
                .flatMap(e -> e.foods().stream())
                .map(WeeklyStoryBuilder::foodName)
                .collect(Collectors.groupingBy(name -> name, LinkedHashMap::new, Collectors.counting()));
        foods.entrySet().stream().max(Map.Entry.comparingByValue()).filter(e -> e.getValue() >= 2)
                .ifPresent(e -> lines.add("가장 자주 남긴 음식은 " + e.getKey() + "(" + e.getValue() + "번)이에요."));

        long noInsulin = week.stream().mapToLong(d -> d.report().episodes().stream()
                .filter(e -> e.effectiveContext() == PhotoContext.MEAL || e.effectiveContext() == PhotoContext.SNACK)
                .filter(e -> d.report().insulinEvents().stream().noneMatch(i ->
                        Math.abs(Duration.between(e.startAt(), i.occurredAt()).toMinutes()) <= 60))
                .count()).sum();
        if (noInsulin > 0) {
            lines.add("앞뒤 1시간 안에 인슐린 기록이 없는 식사·간식은 " + noInsulin + "번이었어요.");
        }
        long drinks = week.stream().flatMap(d -> d.report().episodes().stream())
                .filter(e -> e.effectiveContext() == PhotoContext.ALCOHOL).count();
        if (drinks > 0) {
            lines.add("술 기록은 " + drinks + "번이었어요.");
        }
        for (WeeklyReportResponse.InsightCount insight : insights) {
            if (insight.days() >= 2) {
                lines.add("'" + insight.title() + "' 흐름이 " + insight.days() + "일 보였어요("
                        + insight.dates().stream().map(WeeklyStoryBuilder::weekday).collect(Collectors.joining("·")) + ").");
            }
        }
        long missing = days.stream().filter(d -> d.average() == null).count() - counts.pendingDays();
        if (missing > 0 && !all.isEmpty()) {
            lines.add(missing + "일은 그래프가 없어 이 날의 흐름은 알 수 없어요.");
        }
        return lines;
    }

    private static String foodName(String label) {
        String[] parts = label.trim().split(" ");
        return parts.length > 1 && Character.isDigit(parts[parts.length - 1].charAt(0))
                ? String.join(" ", java.util.Arrays.copyOf(parts, parts.length - 1))
                : label.trim();
    }

    private static String weekday(GlucoseSample sample) {
        return weekday(sample.time().atZone(KST).toLocalDate());
    }

    private static String weekday(LocalDate date) {
        return date.getDayOfWeek().getDisplayName(TextStyle.SHORT, Locale.KOREAN) + "요일";
    }

    private static String copula(int number) {
        return DailyStoryBuilder.lastSound(String.valueOf(number)) == null ? "였어요." : "이었어요.";
    }

    private static String subject(String word) {
        return DailyStoryBuilder.lastSound(word) == null ? "가" : "이";
    }

    private static String direction(int number) {
        Character sound = DailyStoryBuilder.lastSound(String.valueOf(number));
        return sound == null || sound == 'ㄹ' ? "로" : "으로";
    }
}
