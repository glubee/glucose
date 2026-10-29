package com.glucoselog.progress;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Import;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;
import com.glucoselog.auth.AuthTestConfig;

@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(AuthTestConfig.class)
@TestPropertySource(properties = "job.scheduling-enabled=false")
class ProgressFlowTest {
    @Container @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>(DockerImageName.parse("postgres:16-alpine"));
    @Autowired TestRestTemplate rest;
    @Autowired JdbcTemplate jdbc;
    private final LocalDate today = LocalDate.now(ZoneId.of("Asia/Seoul"));

    @Test
    void outOfOrderAndConcurrentDevicesKeepAllDaysAndAwardTheSameMilestoneOnce() {
        String token = login();
        List<Map<String, Object>> newest = new ArrayList<>();
        for (int offset = 6; offset >= 1; offset--) newest.add(close(today.minusDays(offset).toString(), false));
        sync(token, Map.of("operations", newest));
        sync(token, Map.of("operations", List.of(close(today.minusDays(7).toString(), false))));
        assertThat(state(token).get("honeypots")).isEqualTo(1);
        String concurrent = login();
        var first = CompletableFuture.supplyAsync(() -> sync(concurrent, Map.of("operations", newest.subList(0, 3))));
        List<Map<String, Object>> secondBatch = new ArrayList<>(newest.subList(3, 6));
        secondBatch.add(close(today.minusDays(7).toString(), false));
        var second = CompletableFuture.supplyAsync(() -> sync(concurrent, Map.of("operations", secondBatch)));
        assertThat(first.join().getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(second.join().getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat((List<?>) state(concurrent).get("closed_days")).hasSize(7);
        assertThat(state(concurrent).get("honeypots")).isEqualTo(1);
    }

    @Test
    void accountStateRestoresAndIsNotSharedWithAnotherUser() {
        String first = login(), second = login();
        String day = today.minusDays(1).toString();
        Map<String, Object> legacy = Map.of("closed_days", List.of(day), "record_only_days", List.of(day),
                "honeypot_saved_days", List.of(today.minusDays(2).toString()), "honeypots", 2,
                "rest", Map.of("reason", "noSensor", "start", today.toString(), "end", today.plusDays(2).toString()));
        var imported = sync(first, Map.of("legacy_state", legacy, "operations", List.of()));
        assertThat(imported.getStatusCode()).isEqualTo(HttpStatus.OK);
        Map state = state(first);
        assertThat((List<String>) state.get("closed_days")).containsExactly(day);
        assertThat(state.get("honeypots")).isEqualTo(2);
        assertThat(((Map) state.get("rest")).get("reason")).isEqualTo("noSensor");
        assertThat((List<?>) state(second).get("closed_days")).isEmpty();
    }

    @Test
    void retriesAndDuplicateCloseDatesNeverAwardTwiceAndRecordOnlyCanUpgrade() {
        String token = login();
        List<Map<String, Object>> commands = new ArrayList<>();
        for (int offset = 7; offset >= 1; offset--) {
            commands.add(close(today.minusDays(offset).toString(), true));
        }
        var request = Map.of("operations", commands);
        assertThat(sync(token, request).getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(sync(token, request).getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(state(token).get("honeypots")).isEqualTo(1);
        String yesterday = today.minusDays(1).toString();
        assertThat(sync(token, Map.of("operations", List.of(close(yesterday, false), close(yesterday, true))))
                .getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(state(token).get("honeypots")).isEqualTo(1);
        assertThat((List<String>) state(token).get("record_only_days")).doesNotContain(yesterday);
    }

    @Test
    void laterLegacyImportMergesDatesWithoutReplenishingServerBalance() {
        String token = login();
        sync(token, Map.of("legacy_state", Map.of("closed_days", List.of(today.toString()), "honeypots", 0),
                "operations", List.of()));
        String old = today.minusDays(1).toString();
        var legacy = Map.of("closed_days", List.of(old), "honeypots", 2);
        sync(token, Map.of("legacy_state", legacy, "operations", List.of()));
        sync(token, Map.of("legacy_state", legacy, "operations", List.of()));
        assertThat((List<String>) state(token).get("closed_days")).containsExactlyInAnyOrder(old, today.toString());
        assertThat(state(token).get("honeypots")).isEqualTo(0);
    }

    @Test
    void operationIdReuseWithDifferentContentAndMalformedBatchAreRejectedAtomically() {
        String token = login();
        String id = UUID.randomUUID().toString();
        sync(token, Map.of("operations", List.of(Map.of("id", id, "kind", "close_day", "day", today.toString(), "record_only", true))));
        var reused = sync(token, Map.of("operations", List.of(Map.of("id", id, "kind", "close_day", "day", today.minusDays(1).toString()))));
        assertThat(reused.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        String another = login();
        var bad = sync(another, Map.of("operations", List.of(close(today.toString(), false), close("invalid-date", false))));
        assertThat(bad.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat((List<?>) state(another).get("closed_days")).isEmpty();
        var missingDay = sync(another, Map.of("operations", List.of(Map.of("id", UUID.randomUUID().toString(), "kind", "close_day"))));
        assertThat(missingDay.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        var missingReason = sync(another, Map.of("legacy_state",
                Map.of("rest", Map.of("start", today.toString(), "end", today.toString())), "operations", List.of()));
        assertThat(missingReason.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    void futureCompletionAndUnauthorizedReadAreRejectedAndAccountDeletionCascades() {
        String token = login();
        assertThat(sync(token, Map.of("operations", List.of(close(today.plusDays(1).toString(), false))))
                .getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(rest.getForEntity("/v1/progress", Map.class).getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        var result = sync(token, Map.of("operations", List.of(close(today.toString(), false))));
        assertThat(result.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat((List<?>) result.getBody().get("acknowledged_operations")).hasSize(1);
        int before = jdbc.queryForObject("select count(*) from progress_command", Integer.class);
        var deleted = rest.exchange("/v1/me", HttpMethod.DELETE, new HttpEntity<>(headers(token)), Void.class);
        assertThat(deleted.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        assertThat(jdbc.queryForObject("select count(*) from progress_command", Integer.class)).isEqualTo(before - 1);
    }

    private Map<String, Object> close(String day, boolean recordOnly) {
        return Map.of("id", UUID.randomUUID().toString(), "kind", "close_day", "day", day, "record_only", recordOnly);
    }
    private ResponseEntity<Map> sync(String token, Object body) {
        return rest.exchange("/v1/progress/sync", HttpMethod.POST, new HttpEntity<>(body, headers(token)), Map.class);
    }
    private Map state(String token) {
        var response = rest.exchange("/v1/progress", HttpMethod.GET, new HttpEntity<>(headers(token)), Map.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        return (Map) response.getBody().get("state");
    }
    private String login() {
        return (String) rest.postForEntity("/v1/auth/apple", Map.of("identity_token", "valid:" + UUID.randomUUID()), Map.class)
                .getBody().get("access_token");
    }
    private HttpHeaders headers(String token) {
        HttpHeaders headers = new HttpHeaders(); headers.setBearerAuth(token); return headers;
    }
}
