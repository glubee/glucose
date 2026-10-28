package com.glucoselog.report;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

import com.glucoselog.auth.AuthTestConfig;

@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestPropertySource(properties = "job.scheduling-enabled=false")
@Import(AuthTestConfig.class)
class EducationCardFlowTest {
    @Container @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>(DockerImageName.parse("postgres:16-alpine"));
    @Autowired TestRestTemplate rest;
    @Autowired JdbcTemplate jdbc;
    @Autowired EducationCardRepository repository;

    @Test
    void 기존_두_카드를_갱신하고_출처와_검토_이력이_있는_17장을_등록한다() {
        assertThat(repository.count()).isEqualTo(17);
        var daily = repository.findByPlacementAndApprovedTrueOrderBySortOrderAscCodeAsc(EducationCardPlacement.DAILY);
        assertThat(daily).hasSize(7);
        assertThat(daily).extracting(EducationCard::getTrigger).doesNotHaveDuplicates();
        assertThat(daily).allSatisfy(card -> {
            assertThat(card.getBody()).doesNotContain("처치량 조절", "처치량이 많으면");
            assertThat(card.getReviewedBy()).isEqualTo("요청자");
            assertThat(card.getReviewType()).isEqualTo("REQUESTER");
        });
    }

    @Test
    @SuppressWarnings("unchecked")
    void 상시_안내_API는_검토한_10장과_출처를_돌려주고_미승인_카드는_숨긴다() {
        jdbc.update("INSERT INTO education_card (id, code, placement, title, body) VALUES (?, 'UNREVIEWED', 'REVIEW', '초안', '초안')",
                UUID.randomUUID());
        try {
            var login = rest.postForEntity("/v1/auth/apple", Map.of("identity_token", "valid:" + UUID.randomUUID()), Map.class);
            var headers = new HttpHeaders();
            headers.setBearerAuth((String) login.getBody().get("access_token"));
            var response = rest.exchange("/v1/education-cards/review", HttpMethod.GET, new HttpEntity<>(headers), List.class);
            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            List<Map<String, Object>> cards = response.getBody();
            assertThat(cards).hasSize(10);
            assertThat(cards.getFirst().get("code")).isEqualTo("REVIEW_01");
            assertThat(cards.getLast().get("code")).isEqualTo("REVIEW_10");
            assertThat(cards).allSatisfy(card -> {
                assertThat(card.get("trigger")).isNull();
                assertThat(card.get("reviewed_at")).isEqualTo("2026-10-28");
                assertThat(card.get("review_type")).isEqualTo("REQUESTER");
                assertThat((List<?>) card.get("sources")).isNotEmpty();
            });
        } finally {
            jdbc.update("DELETE FROM education_card WHERE code = 'UNREVIEWED'");
        }
    }

    @Test
    void 상시_안내_API도_인증이_필요하다() {
        assertThat(rest.getForEntity("/v1/education-cards/review", String.class).getStatusCode())
                .isEqualTo(HttpStatus.UNAUTHORIZED);
    }
}
