package com.glucoselog.report;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

public record WeeklyReportResponse(
        LocalDate weekStart,
        LocalDate weekEnd,
        int daysWithData,
        int daysInsufficient,
        BigDecimal averageGlucose,
        int episodesCount,
        int reboundCount,
        int insulinEventsCount,
        int sufficientDays,
        int lowCoverageDays,
        int pendingDays,
        List<String> summary,
        List<String> story,
        List<Day> days,
        List<TimeBand> timeBands,
        List<InsightCount> insights) {

    /** 요일별 한 줄. 그래프가 없으면 average/min/max가 null */
    public record Day(LocalDate date, BigDecimal average, Integer min, Integer max, BigDecimal coverageRatio,
            int intakeCount, int insulinCount, int lowCount, List<String> insightCodes) {
    }

    /** 시간대(새벽 0~6, 오전 6~12, 오후 12~18, 저녁 18~24)별 읽힌 값 평균. 값이 없으면 null */
    public record TimeBand(String label, int startHour, int endHour, BigDecimal average, Integer min, Integer max, int readingsCount) {
    }

    /** 이번 주 흐름 안내가 나온 횟수(서버 설정이 켜졌을 때만) */
    public record InsightCount(String code, String title, int days, List<LocalDate> dates) {
    }

    public WeeklyReportResponse {
        story = story == null ? List.of() : List.copyOf(story);
        days = days == null ? List.of() : List.copyOf(days);
        timeBands = timeBands == null ? List.of() : List.copyOf(timeBands);
        insights = insights == null ? List.of() : List.copyOf(insights);
    }

    public WeeklyReportResponse(LocalDate weekStart, LocalDate weekEnd, int daysWithData, int daysInsufficient,
            BigDecimal averageGlucose, int episodesCount, int reboundCount, int insulinEventsCount, int sufficientDays,
            int lowCoverageDays, int pendingDays, List<String> summary) {
        this(weekStart, weekEnd, daysWithData, daysInsufficient, averageGlucose, episodesCount, reboundCount,
                insulinEventsCount, sufficientDays, lowCoverageDays, pendingDays, summary, List.of(), List.of(), List.of(), List.of());
    }

    WeeklyReportResponse withSummary(List<String> summary) {
        return new WeeklyReportResponse(
                weekStart, weekEnd, daysWithData, daysInsufficient, averageGlucose, episodesCount, reboundCount,
                insulinEventsCount, sufficientDays, lowCoverageDays, pendingDays, summary, story, days, timeBands, insights);
    }

    WeeklyReportResponse withDetails(List<String> story, List<Day> days, List<TimeBand> timeBands, List<InsightCount> insights) {
        return new WeeklyReportResponse(
                weekStart, weekEnd, daysWithData, daysInsufficient, averageGlucose, episodesCount, reboundCount,
                insulinEventsCount, sufficientDays, lowCoverageDays, pendingDays, summary, story, days, timeBands, insights);
    }
}
