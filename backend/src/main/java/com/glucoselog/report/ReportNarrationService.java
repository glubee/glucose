package com.glucoselog.report;

import static com.glucoselog.report.NarrativeFact.Definition.*;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class ReportNarrationService {
    private static final List<String> LIMITATIONS = List.of(
            "혈당 수치는 그래프 이미지에서 읽은 추정값이며 센서 원본 데이터가 아니에요.",
            "읽히지 않은 구간은 비워 두고 계산에서 제외했어요. 그래프 상·하단에 붙은 값은 경계 표시예요.",
            "섭취·인슐린 기록은 사용자가 입력한 기록이에요. 이 요약은 혈당 변화의 원인이나 치료 방법을 판단하지 않아요.");
    private final ReportNarrationClient client;
    private final ObjectMapper mapper;

    public ReportNarrationService(ReportNarrationClient client, ObjectMapper mapper) {
        this.client = client;
        this.mapper = mapper;
    }

    public ReportNarrativeResponse daily(DailyReportResponse report) {
        var glucose = report.glucose();
        List<NarrativeFact> facts = List.of(
                COVERAGE.fact(glucose == null || glucose.coverageRatio() == null ? null : glucose.coverageRatio().multiply(BigDecimal.valueOf(100))),
                READINGS.fact(glucose == null ? null : glucose.readingsCount()),
                AVERAGE.fact(glucose == null ? null : glucose.average()),
                MINIMUM.fact(glucose == null ? null : glucose.min()),
                MAXIMUM.fact(glucose == null ? null : glucose.max()),
                INTAKES.fact(report.episodes().stream().mapToInt(EpisodeSummary::intakeCount).sum()),
                INSULIN.fact(report.insulinEventsCount()));
        return narrate("DAILY", facts);
    }

    public ReportNarrativeResponse weekly(WeeklyReportResponse report) {
        return narrate("WEEKLY", List.of(
                DATA_DAYS.fact(report.daysWithData()), SUFFICIENT_DAYS.fact(report.sufficientDays()),
                LIMITED_DAYS.fact(report.lowCoverageDays()), PENDING_DAYS.fact(report.pendingDays()),
                MISSING_DAYS.fact(report.daysInsufficient()), AVERAGE.fact(report.averageGlucose()),
                GROUPS.fact(report.episodesCount()), INSULIN.fact(report.insulinEventsCount()),
                ABOVE.fact(report.reboundCount())));
    }

    private ReportNarrativeResponse narrate(String kind, List<NarrativeFact> facts) {
        try {
            String raw = client.plan(kind, facts);
            if (raw != null) {
                var paragraphs = validateAndRender(mapper.readTree(raw), facts);
                return new ReportNarrativeResponse(kind, "AI", paragraphs, facts, LIMITATIONS);
            }
        } catch (Exception error) {
            // Do not log returned text, fact values or provider exception bodies.
        }
        List<ReportNarrativeResponse.Paragraph> paragraphs = new ArrayList<>();
        for (int i = 0; i < facts.size(); i += 3) {
            var group = facts.subList(i, Math.min(i+3, facts.size()));
            paragraphs.add(new ReportNarrativeResponse.Paragraph(
                    group.stream().map(fact -> fact.render("PLAIN")).collect(Collectors.joining(" ")),
                    group.stream().map(NarrativeFact::id).toList()));
        }
        return new ReportNarrativeResponse(kind, "TEMPLATE", paragraphs, facts, LIMITATIONS);
    }

    private List<ReportNarrativeResponse.Paragraph> validateAndRender(JsonNode response, List<NarrativeFact> facts) {
        JsonNode plans = response.path("paragraphs");
        if (!plans.isArray() || plans.isEmpty() || plans.size() > 3) {
            throw new IllegalArgumentException("invalid paragraph count");
        }
        Map<String, NarrativeFact> byId = facts.stream().collect(Collectors.toMap(NarrativeFact::id, Function.identity()));
        var seen = new HashSet<String>();
        List<ReportNarrativeResponse.Paragraph> paragraphs = new ArrayList<>();
        for (JsonNode plan : plans) {
            String style = plan.path("style").asText();
            JsonNode ids = plan.path("fact_ids");
            if (!("PLAIN".equals(style) || "CONCISE".equals(style)) || !ids.isArray()
                    || ids.isEmpty() || ids.size() > facts.size()) {
                throw new IllegalArgumentException("invalid plan");
            }
            List<String> factIds = new ArrayList<>();
            List<String> sentences = new ArrayList<>();
            for (JsonNode node : ids) {
                if (!node.isTextual() || !byId.containsKey(node.asText()) || !seen.add(node.asText())) {
                    throw new IllegalArgumentException("invalid fact reference");
                }
                factIds.add(node.asText());
                sentences.add(byId.get(node.asText()).render(style));
            }
            paragraphs.add(new ReportNarrativeResponse.Paragraph(String.join(" ", sentences), List.copyOf(factIds)));
        }
        if (!seen.equals(byId.keySet())) {
            throw new IllegalArgumentException("missing fact reference");
        }
        return List.copyOf(paragraphs);
    }
}
