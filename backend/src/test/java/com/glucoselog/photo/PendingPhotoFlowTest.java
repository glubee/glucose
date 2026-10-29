package com.glucoselog.photo;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;

import java.net.URI;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Import;
import org.springframework.http.*;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;
import com.glucoselog.auth.AppUserRepository;
import com.glucoselog.auth.AuthTestConfig;

@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(AuthTestConfig.class)
@TestPropertySource(properties = "job.scheduling-enabled=false")
class PendingPhotoFlowTest {
    @Container @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>(DockerImageName.parse("postgres:16-alpine"));
    @Autowired TestRestTemplate rest;
    @Autowired IntakePhotoRepository photos;
    @Autowired AppUserRepository users;
    @MockitoBean PhotoStorageService storage;
    private record Session(String token, UUID userId) {}

    @BeforeEach void mockOnlyObjectStorage() throws Exception {
        when(storage.presignPut(anyString(), anyString())).thenReturn(URI.create("https://storage.invalid/upload").toURL());
        when(storage.exists(anyString())).thenReturn(true);
    }

    @Test
    void startIsCompatibleAndClientIdentityResumesTheSameUpload() {
        Session user = login();
        var legacy = request(user, HttpMethod.POST, "/v1/photos", Map.of("content_type", "image/jpeg", "context", "MEAL"));
        assertThat(legacy.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        String clientID = UUID.randomUUID().toString();
        var body = Map.of("content_type", "image/jpeg", "context", "SNACK", "client_id", clientID,
                "captured_at", "2026-10-29T01:02:03.123456Z");
        var first = request(user, HttpMethod.POST, "/v1/photos", body);
        var second = request(user, HttpMethod.POST, "/v1/photos", body);
        assertThat(first.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(second.getBody().get("photo_id")).isEqualTo(first.getBody().get("photo_id"));
        request(user, HttpMethod.POST, "/v1/photos/" + first.getBody().get("photo_id") + "/complete", null);
        var resumed = request(user, HttpMethod.POST, "/v1/photos", body);
        assertThat(resumed.getBody().get("photo_id")).isEqualTo(first.getBody().get("photo_id"));
        assertThat(resumed.getBody().get("uploaded")).isEqualTo(true);
    }

    @Test
    void pendingListPreservesCaptureTimeClassificationAndEqualTimePagination() {
        Session user = login();
        UUID first = uploaded(user), second = uploaded(user);
        String capture = "2026-10-29T01:02:03.123456Z";
        for (UUID id : List.of(first, second)) {
            assertThat(request(user, HttpMethod.PATCH, "/v1/photos/" + id + "/metadata",
                    Map.of("captured_at", capture, "client_id", UUID.randomUUID().toString(), "context", "SNACK"))
                    .getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        }
        var page = request(user, HttpMethod.GET, "/v1/photos?unconfirmed=true&limit=1", null);
        assertThat(page.getStatusCode()).isEqualTo(HttpStatus.OK);
        Map item = ((List<Map>) page.getBody().get("items")).get(0);
        assertThat(item.get("captured_at")).isEqualTo(capture);
        assertThat(item.get("context")).isEqualTo("SNACK");
        assertThat(item).doesNotContainKeys("url", "object_key", "upload_url");
        var next = request(user, HttpMethod.GET, "/v1/photos?unconfirmed=true&limit=1&cursor=" + page.getBody().get("next_cursor"), null);
        Map nextItem = ((List<Map>) next.getBody().get("items")).get(0);
        assertThat(nextItem.get("photo_id")).isNotEqualTo(item.get("photo_id"));
    }

    @Test
    void confirmationSurvivesIntakeDeletionAndCannotBeChangedByAnotherUser() {
        Session owner = login(), stranger = login();
        UUID id = uploaded(owner);
        assertThat(request(stranger, HttpMethod.GET, "/v1/photos/" + id, null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(request(stranger, HttpMethod.POST, "/v1/photos/" + id + "/dismiss", null).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        var body = Map.of("context", "MEAL", "occurred_at", "2026-10-29T01:00:00Z", "photo_id", id.toString(),
                "items", List.of(Map.of("name", "합성 음식")));
        assertThat(request(stranger, HttpMethod.POST, "/v1/intakes", body).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        var created = request(owner, HttpMethod.POST, "/v1/intakes", body);
        assertThat(created.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(request(owner, HttpMethod.GET, "/v1/photos/" + id, null).getBody().get("confirmed")).isEqualTo(true);
        request(owner, HttpMethod.DELETE, "/v1/intakes/" + created.getBody().get("id"), null);
        assertThat((List<?>) request(owner, HttpMethod.GET, "/v1/photos?unconfirmed=true", null).getBody().get("items")).isEmpty();
    }

    @Test
    void dismissIsIdempotentAndLateCompletionDoesNotResurrectAPhoto() {
        Session user = login();
        var started = request(user, HttpMethod.POST, "/v1/photos", Map.of("content_type", "image/jpeg", "context", "MEAL"));
        String id = (String) started.getBody().get("photo_id");
        assertThat(request(user, HttpMethod.POST, "/v1/photos/" + id + "/dismiss", null).getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        assertThat(request(user, HttpMethod.POST, "/v1/photos/" + id + "/dismiss", null).getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        assertThat(request(user, HttpMethod.POST, "/v1/photos/" + id + "/complete", null).getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(request(user, HttpMethod.GET, "/v1/photos/" + id, null).getBody().get("dismissed")).isEqualTo(true);
        assertThat((List<?>) request(user, HttpMethod.GET, "/v1/photos?unconfirmed=true", null).getBody().get("items")).isEmpty();
    }

    private UUID uploaded(Session user) {
        IntakePhoto photo = new IntakePhoto(user.userId(), "photos/test-" + UUID.randomUUID() + ".jpg", "image/jpeg", PhotoContext.MEAL);
        photo.markUploaded(Instant.now());
        return photos.saveAndFlush(photo).getId();
    }
    private Session login() {
        String subject = UUID.randomUUID().toString();
        Map result = rest.postForEntity("/v1/auth/apple", Map.of("identity_token", "valid:" + subject), Map.class).getBody();
        return new Session((String) result.get("access_token"), users.findByAppleSub(subject).orElseThrow().getId());
    }
    private ResponseEntity<Map> request(Session user, HttpMethod method, String path, Object body) {
        HttpHeaders headers = new HttpHeaders(); headers.setBearerAuth(user.token());
        return rest.exchange(path, method, new HttpEntity<>(body, headers), Map.class);
    }
}
