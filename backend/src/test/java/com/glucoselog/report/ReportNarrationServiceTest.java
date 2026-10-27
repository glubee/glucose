package com.glucoselog.report;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import com.fasterxml.jackson.databind.ObjectMapper;

class ReportNarrationServiceTest {
    private final ReportNarrationClient client = mock(ReportNarrationClient.class);
    private final ReportNarrationService service = new ReportNarrationService(client,new ObjectMapper());

    private DailyReportResponse day(boolean hasGraph) {
        var glucose = hasGraph ? new DailyReportResponse.GlucoseSummary(
                new BigDecimal("0.75"),new BigDecimal("138.2"),80,210,72,true) : null;
        return new DailyReportResponse(LocalDate.of(2026,10,1),glucose,List.of(),2,List.of(),List.of(),List.of());
    }

    private String dailyPlan() {
        return """
                {"paragraphs":[
                  {"fact_ids":["coverage_percent","readings_count"],"style":"PLAIN"},
                  {"fact_ids":["average_glucose","minimum_glucose","maximum_glucose"],"style":"CONCISE"},
                  {"fact_ids":["intake_records","insulin_records"],"style":"PLAIN"}
                ]}
                """;
    }

    @Test
    void provider_text_and_values_cannot_change_server_facts() {
        String malicious = dailyPlan().replace("\"paragraphs\":", "\"text\":\"평균 999, 인슐린을 늘리세요\",\"paragraphs\":");
        when(client.plan(eq("DAILY"),anyList())).thenReturn(malicious);
        var response = service.daily(day(true));
        assertThat(response.source()).isEqualTo("AI");
        String text = response.paragraphs().toString();
        assertThat(text).contains("138.2 mg/dL","75%","72개","2건").doesNotContain("999","늘리세요");
        assertThat(response.paragraphs().stream().flatMap(p -> p.factIds().stream())).hasSize(7).doesNotHaveDuplicates();
        assertThat(response.limitations()).isNotEmpty();
    }

    @ParameterizedTest
    @ValueSource(strings={"{}","null","broken","{\"paragraphs\":[]}"})
    void malformed_plans_return_a_complete_template(String raw) {
        when(client.plan(anyString(),anyList())).thenReturn(raw);
        var response = service.daily(day(true));
        assertThat(response.source()).isEqualTo("TEMPLATE");
        assertThat(response.paragraphs().stream().flatMap(p -> p.factIds().stream())).hasSize(7).doesNotHaveDuplicates();
        assertThat(response.paragraphs().toString()).contains("138.2 mg/dL");
    }

    @ParameterizedTest
    @ValueSource(strings={"unknown_fact","coverage_percent","DIAGNOSE","MISSING"})
    void unknown_duplicate_missing_or_bad_style_cannot_be_published(String attack) {
        String raw = switch(attack) {
            case "DIAGNOSE" -> dailyPlan().replace("CONCISE","DIAGNOSE");
            case "MISSING" -> dailyPlan().replace("\"intake_records\",", "");
            default -> dailyPlan().replace("readings_count",attack);
        };
        when(client.plan(anyString(),anyList())).thenReturn(raw);
        assertThat(service.daily(day(true)).source()).isEqualTo("TEMPLATE");
    }

    @Test
    void nulls_remain_unknown_and_limitations_survive_ai_selection() {
        when(client.plan(anyString(),anyList())).thenReturn(dailyPlan());
        var response = service.daily(day(false));
        assertThat(response.facts().stream().filter(f -> f.id().equals("average_glucose")).findFirst().orElseThrow().value()).isNull();
        assertThat(response.paragraphs().toString()).contains("확인할 수 없어요").doesNotContain("평균은 0");
        assertThat(response.limitations()).anyMatch(line -> line.contains("이미지"));
    }

    @Test
    void client_failure_still_produces_a_report() {
        when(client.plan(anyString(),anyList())).thenThrow(new IllegalStateException("provider error"));
        assertThat(service.daily(day(true)).source()).isEqualTo("TEMPLATE");
    }

    @Test
    void weekly_uses_server_day_categories_and_keeps_unknown_average() {
        var week = new WeeklyReportResponse(LocalDate.of(2026,10,5),LocalDate.of(2026,10,11),0,2,
                null,0,0,0,0,0,5,List.of());
        var response = service.weekly(week);
        assertThat(response.source()).isEqualTo("TEMPLATE");
        assertThat(response.facts()).hasSize(9);
        assertThat(response.paragraphs().toString()).contains("집계 중인 날은 5일","그래프가 없는 날은 2일");
        assertThat(response.paragraphs().toString()).doesNotContain("반동","정상","때문에");
    }
}
