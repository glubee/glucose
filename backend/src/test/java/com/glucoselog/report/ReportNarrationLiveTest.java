package com.glucoselog.report;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.net.ServerSocket;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.glucoselog.ml.MlServiceProperties;
import com.glucoselog.photo.PhotoContext;

/** Opt-in smoke test: local ML HTTP -> actual AI plan -> production Java renderer.
 * Uses synthetic report aggregates only. Ordinary test runs do not call an AI provider. */
@EnabledIfEnvironmentVariable(named="REPORT_NARRATION_SMOKE_URL", matches="http://127\\.0\\.0\\.1:[0-9]+")
class ReportNarrationLiveTest {
    @Test
    void daily_weekly_missing_and_offline_reports_remain_grounded() throws Exception {
        var mapper = new ObjectMapper().setPropertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE);
        var client = new ReportNarrationClient(
                new MlServiceProperties(System.getenv("REPORT_NARRATION_SMOKE_URL"),"synthetic-report-token",1000,11000),
                new ReportNarrationProperties(true,11000));
        var service = new ReportNarrationService(client,mapper);
        var day = new DailyReportResponse(LocalDate.of(2026,10,26),
                new DailyReportResponse.GlucoseSummary(new BigDecimal("0.75"),new BigDecimal("138.2"),80,210,72,true),
                List.of(new EpisodeSummary(Instant.parse("2026-10-26T00:00:00Z"),PhotoContext.MEAL,PhotoContext.MEAL,
                        false,Instant.parse("2026-10-26T04:00:00Z"),null,3)),
                2,List.of(),List.of(),List.of());
        var week = new WeeklyReportResponse(LocalDate.of(2026,10,19),LocalDate.of(2026,10,25),5,0,
                new BigDecimal("142.7"),12,1,10,4,1,2,List.of());
        var missing = new DailyReportResponse(LocalDate.of(2026,10,26),null,List.of(),0,List.of(),List.of(),List.of());

        var normal = service.daily(day);
        assertThat(normal.source()).isEqualTo("AI");
        assertThat(normal.paragraphs().toString()).contains("138.2 mg/dL","75%","72개","3건","2건");
        assertGrounded(normal,7);

        var weekly = service.weekly(week);
        assertThat(weekly.source()).isEqualTo("AI");
        assertThat(weekly.paragraphs().toString()).contains("142.7 mg/dL","5일","4일","1일","2일","12건","10건");
        assertGrounded(weekly,9);

        var noGraph = service.daily(missing);
        assertThat(noGraph.source()).isEqualTo("AI");
        assertThat(noGraph.facts().stream().filter(f -> f.id().equals("average_glucose")).findFirst().orElseThrow().value()).isNull();
        assertThat(noGraph.paragraphs().toString()).contains("확인할 수 없어요").doesNotContain("평균은 0");
        assertGrounded(noGraph,7);

        int offlinePort;
        try (var socket = new ServerSocket(0,1,java.net.InetAddress.getByName("127.0.0.1"))) {
            offlinePort = socket.getLocalPort();
        }
        var offline = new ReportNarrationService(new ReportNarrationClient(
                new MlServiceProperties("http://127.0.0.1:"+offlinePort,"synthetic-report-token",200,200),
                new ReportNarrationProperties(true,200)),mapper).daily(day);
        assertThat(offline.source()).isEqualTo("TEMPLATE");
        assertThat(offline.facts()).isEqualTo(normal.facts());
        assertGrounded(offline,7);

        String output = System.getenv("REPORT_NARRATION_SMOKE_OUTPUT");
        if (output != null) {
            var samples = new LinkedHashMap<String,Object>();
            samples.put("synthetic_data_only",true);
            samples.put("daily",normal);
            samples.put("weekly",weekly);
            samples.put("missing_graph",noGraph);
            samples.put("ai_offline",offline);
            Files.writeString(Path.of(output),mapper.writerWithDefaultPrettyPrinter().writeValueAsString(samples));
        }
    }

    private void assertGrounded(ReportNarrativeResponse report, int factCount) {
        assertThat(report.paragraphs()).hasSizeBetween(1,3);
        assertThat(report.paragraphs().stream().flatMap(p -> p.factIds().stream())).hasSize(factCount).doesNotHaveDuplicates();
        assertThat(report.paragraphs().toString()).doesNotContain("때문에","정상","위험","늘리세요","줄이세요");
        assertThat(report.limitations()).hasSize(3);
    }
}
