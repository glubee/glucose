package com.glucoselog.report;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

/**
 * glucose가 null이면 그날 분석 완료된 그래프가 없다는 뜻이다(판단 불가).
 * story는 하루 이야기(시간순 문장 목록, DailyStoryBuilder). 앱은 한 문단으로 이어 보여주고, summary는 근거로 둔다.
 */
public record DailyReportResponse(
        LocalDate date,
        GlucoseSummary glucose,
        List<EpisodeSummary> episodes,
        int insulinEventsCount,
        List<InsulinEventMarker> insulinEvents,
        List<EducationCardResponse> educationCards,
        List<String> summary,
        int reboundGlucoseThreshold,
        List<String> story,
        List<ReportInsight> insights) {

    public DailyReportResponse {
        story = story == null ? List.of() : List.copyOf(story);
        insights = insights == null ? List.of() : List.copyOf(insights);
    }

    public DailyReportResponse(LocalDate date, GlucoseSummary glucose, List<EpisodeSummary> episodes, int insulinEventsCount,
            List<InsulinEventMarker> insulinEvents, List<EducationCardResponse> educationCards, List<String> summary,
            int reboundGlucoseThreshold, List<String> story) {
        this(date, glucose, episodes, insulinEventsCount, insulinEvents, educationCards, summary, reboundGlucoseThreshold, story, List.of());
    }

    public DailyReportResponse(LocalDate date, GlucoseSummary glucose, List<EpisodeSummary> episodes, int insulinEventsCount,
            List<InsulinEventMarker> insulinEvents, List<EducationCardResponse> educationCards, List<String> summary,
            int reboundGlucoseThreshold) {
        this(date, glucose, episodes, insulinEventsCount, insulinEvents, educationCards, summary, reboundGlucoseThreshold, List.of(), List.of());
    }

    /** sufficient는 coverage_ratio가 설정 기준 이상인지의 기록 상태일 뿐, 혈당 평가가 아니다. */
    public record GlucoseSummary(
            BigDecimal coverageRatio, BigDecimal average, Integer min, Integer max, int readingsCount, boolean sufficient) {
    }

    /** 그래프 위에 표시할 인슐린 기록(입력된 사실만, 시각순). */
    public record InsulinEventMarker(Instant occurredAt, BigDecimal units, String kind) {
    }
}
