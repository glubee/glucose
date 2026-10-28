package com.glucoselog.glucose;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.io.ByteArrayOutputStream;
import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Font;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

import com.glucoselog.auth.AuthTestConfig;
import com.glucoselog.job.Job;
import com.glucoselog.job.JobHandler;
import com.glucoselog.job.JobRepository;
import com.glucoselog.job.JobService;
import com.glucoselog.job.JobStatus;
import com.sun.net.httpserver.HttpServer;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.model.CreateBucketRequest;

/** 그래프 업로드 완료 → GRAPH_PARSE job 적재 → 워커가 ml-service를 호출해 glucose_reading에 반영하는 전체 흐름. */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(AuthTestConfig.class)
class GlucoseGraphFlowTest {

    private static final String BUCKET = "glucose-photos";

    private static final String SUCCESS_BODY = """
            {
              "date": "2026-10-01",
              "source": "LIBRE_DAILY_GRAPH",
              "unit": "mg/dL",
              "interval_minutes": 15,
              "readings": [
                {"time": "00:00", "value": 120, "flag": "NORMAL"},
                {"time": "00:15", "value": 125, "flag": "NORMAL"},
                {"time": "00:30", "value": null, "flag": "MISSING"}
              ],
              "gaps": [{"from": "00:30", "to": "00:45"}],
              "coverage_ratio": 0.94,
              "meta": {"parser_version": "1.1.5", "image_width": 1179, "image_height": 2029, "latency_ms": 320}
            }
            """;

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>(DockerImageName.parse("postgres:16-alpine"));

    @Container
    static GenericContainer<?> s3mock = new GenericContainer<>(DockerImageName.parse("adobe/s3mock:latest"))
            .withExposedPorts(9090);

    private static HttpServer mlServiceStub;
    private static volatile int mlServiceStatus = 200;
    private static volatile String mlServiceBody = SUCCESS_BODY;
    private static volatile boolean forwardToNativeMl;

    private static String s3Endpoint() {
        return "http://%s:%d".formatted(s3mock.getHost(), s3mock.getMappedPort(9090));
    }

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) throws IOException {
        registry.add("r2.endpoint", GlucoseGraphFlowTest::s3Endpoint);
        registry.add("r2.access-key-id", () -> "test");
        registry.add("r2.secret-access-key", () -> "test");
        registry.add("r2.photo-bucket", () -> BUCKET);

        mlServiceStub = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        mlServiceStub.createContext("/v1/graph/parse", exchange -> {
            byte[] requestBytes = exchange.getRequestBody().readAllBytes();
            if (forwardToNativeMl) {
                try {
                    var forwarded = HttpClient.newBuilder().version(HttpClient.Version.HTTP_1_1).build().send(HttpRequest.newBuilder(
                                    URI.create(System.getenv("GRAPH_PIPELINE_SMOKE_URL") + "/v1/graph/parse"))
                            .header("Content-Type", exchange.getRequestHeaders().getFirst("Content-Type"))
                            .header("X-Internal-Token", "test-token")
                            .POST(HttpRequest.BodyPublishers.ofByteArray(requestBytes)).build(),
                            HttpResponse.BodyHandlers.ofString());
                    mlServiceStatus = forwarded.statusCode();
                    mlServiceBody = forwarded.body();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new IOException(e);
                }
            }
            byte[] bytes = mlServiceBody.getBytes();
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(mlServiceStatus, bytes.length);
            exchange.getResponseBody().write(bytes);
            exchange.close();
        });
        mlServiceStub.start();
        registry.add("ml.service-url", () -> "http://127.0.0.1:" + mlServiceStub.getAddress().getPort());
        registry.add("ml.internal-token", () -> "test-token");
        registry.add("job.retry-backoff-seconds", () -> 0);
        registry.add("job.scheduling-enabled", () -> false);
    }

    @BeforeAll
    static void createBucket() {
        try (S3Client client = S3Client.builder()
                .endpointOverride(URI.create(s3Endpoint()))
                .region(Region.of("auto"))
                .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create("test", "test")))
                .serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(true).build())
                .build()) {
            client.createBucket(CreateBucketRequest.builder().bucket(BUCKET).build());
        }
    }

    @AfterEach
    void resetStub() {
        mlServiceStatus = 200;
        mlServiceBody = SUCCESS_BODY;
        forwardToNativeMl = false;
    }

    @Autowired
    TestRestTemplate rest;

    @Autowired
    JobRepository jobRepository;

    @Autowired
    JobService jobService;

    @Autowired
    GlucoseGraphUploadRepository uploadRepository;

    @Autowired
    GlucoseReadingRepository readingRepository;

    @Autowired
    GraphParseJobHandler graphParseJobHandler;

    private final HttpClient httpClient = HttpClient.newHttpClient();

    @Test
    void 업로드_완료_후_워커가_처리하면_readings가_저장되고_상태조회로_날짜와_coverage를_볼_수_있다() throws Exception {
        String accessToken = login();
        UUID uploadId = uploadAndComplete(accessToken);

        runWorkerOnce();

        Job job = findJobForUpload(uploadId);
        assertThat(job.getStatus()).isEqualTo(JobStatus.DONE);

        ResponseEntity<Map> status = getStatus(accessToken, uploadId);
        assertThat(status.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(status.getBody().get("date")).isEqualTo("2026-10-01");

        List<GlucoseReading> readings = readingRepository.findByUploadIdOrderByTimeSlot(uploadId);
        assertThat(readings).hasSize(3);
        assertThat(readings.get(0).getValue()).isEqualTo(120);
        assertThat(readings.get(2).getValue()).isNull();
        assertThat(readings.get(2).getFlag()).isEqualTo(ReadingFlag.MISSING);

        ResponseEntity<Map> byDate = rest.exchange(
                "/v1/glucose-readings/2026-10-01",
                HttpMethod.GET,
                new HttpEntity<>(authHeaders(accessToken)),
                Map.class);
        assertThat(byDate.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat((List<?>) byDate.getBody().get("readings")).hasSize(3);
    }

    @Test
    void 같은_날짜로_재업로드하면_기존_업로드는_지워지고_새_업로드로_덮어써진다() throws Exception {
        String accessToken = login();

        UUID firstUploadId = uploadAndComplete(accessToken);
        runWorkerOnce();
        assertThat(uploadRepository.findById(firstUploadId)).isPresent();

        UUID secondUploadId = uploadAndComplete(accessToken);
        runWorkerOnce();

        assertThat(uploadRepository.findById(firstUploadId)).isEmpty();
        assertThat(readingRepository.findByUploadIdOrderByTimeSlot(firstUploadId)).isEmpty();

        assertThat(uploadRepository.findById(secondUploadId)).isPresent();
        assertThat(readingRepository.findByUploadIdOrderByTimeSlot(secondUploadId)).hasSize(3);
    }

    @Test
    void 처리가_끝나기_전에_상태를_물으면_409() throws Exception {
        String accessToken = login();
        UUID uploadId = uploadAndComplete(accessToken);

        ResponseEntity<Map> status = getStatus(accessToken, uploadId);

        assertThat(status.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(status.getBody().get("code")).isEqualTo("GRAPH_NOT_READY");
    }

    @Test
    void ml_service가_422를_내리면_재시도_없이_바로_FAILED가_되고_상태조회는_422() throws Exception {
        mlServiceStatus = 422;
        mlServiceBody = "{\"code\":\"GRAPH_NOT_RECOGNIZED\",\"message\":\"격자선을 찾지 못했습니다\"}";
        String accessToken = login();
        UUID uploadId = uploadAndComplete(accessToken);

        runWorkerOnce();

        Job job = findJobForUpload(uploadId);
        assertThat(job.getStatus()).isEqualTo(JobStatus.FAILED);
        assertThat(job.getAttempts()).isEqualTo(1); // 재시도 없이 바로 FAILED

        ResponseEntity<Map> status = getStatus(accessToken, uploadId);
        assertThat(status.getStatusCode()).isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
        assertThat(status.getBody().get("code")).isEqualTo("GRAPH_NOT_RECOGNIZED");
    }

    @Test
    void ml_service가_TOO_LITTLE_DATA를_내리면_상태조회_코드도_구분된다() throws Exception {
        mlServiceStatus = 422;
        mlServiceBody = "{\"code\":\"TOO_LITTLE_DATA\",\"message\":\"곡선이 하루의 10% 미만입니다\"}";
        String accessToken = login();
        UUID uploadId = uploadAndComplete(accessToken);

        runWorkerOnce();

        ResponseEntity<Map> status = getStatus(accessToken, uploadId);
        assertThat(status.getStatusCode()).isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
        assertThat(status.getBody().get("code")).isEqualTo("GRAPH_TOO_LITTLE_DATA");
    }

    @Test
    void 알려지지_않은_실패는_일반_GRAPH_PARSE_FAILED() throws Exception {
        mlServiceStatus = 400;
        mlServiceBody = "{\"code\":\"INVALID_IMAGE\",\"message\":\"이미지가 아닙니다\"}";
        String accessToken = login();
        UUID uploadId = uploadAndComplete(accessToken);

        runWorkerOnce();

        ResponseEntity<Map> status = getStatus(accessToken, uploadId);
        assertThat(status.getStatusCode()).isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
        assertThat(status.getBody().get("code")).isEqualTo("GRAPH_PARSE_FAILED");
    }

    @Test
    void 다른_사용자의_날짜_데이터는_404() {
        String accessToken = login();

        ResponseEntity<Map> response = rest.exchange(
                "/v1/glucose-readings/2026-01-01",
                HttpMethod.GET,
                new HttpEntity<>(authHeaders(accessToken)),
                Map.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(response.getBody().get("code")).isEqualTo("GLUCOSE_DAY_NOT_FOUND");
    }

    @Test
    void 오래된_분석기가_성공을_반환해도_수치를_저장하지_않는다() throws Exception {
        mlServiceBody = SUCCESS_BODY.replace("1.1.5", "1.0.0");
        String token = login();
        UUID uploadId = uploadAndComplete(token);
        runWorkerOnce();
        assertThat(findJobForUpload(uploadId).getStatus()).isEqualTo(JobStatus.FAILED);
        assertThat(readingRepository.findByUploadIdOrderByTimeSlot(uploadId)).isEmpty();
        var response = getStatus(token, uploadId);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        assertThat(response.getBody().get("code")).isEqualTo("GRAPH_PARSER_OUTDATED");
    }

    @Test
    void 과거_잘못된_결과를_숨기고_저장된_원본으로_한번만_재분석해_복구한다() throws Exception {
        String token = login();
        mlServiceBody = SUCCESS_BODY.replace("\"value\": 120", "\"value\": 240");
        UUID uploadId = uploadAndComplete(token);
        runWorkerOnce();
        var upload = uploadRepository.findById(uploadId).orElseThrow();
        upload.applyParseResult(upload.getResultDate(), upload.getCoverageRatio(), "1.0.0");
        uploadRepository.save(upload);
        UUID previousJob = upload.getParseJobId();

        var stale = rest.exchange("/v1/glucose-readings/2026-10-01", HttpMethod.GET,
                new HttpEntity<>(authHeaders(token)), Map.class);
        assertThat(stale.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(stale.getBody().get("code")).isEqualTo("GRAPH_REPROCESS_REQUIRED");
        var daily = rest.exchange("/v1/reports/daily/2026-10-01", HttpMethod.GET,
                new HttpEntity<>(authHeaders(token)), Map.class);
        assertThat(daily.getBody().get("glucose")).isNull();
        var weekly = rest.exchange("/v1/reports/weekly/2026-10-01", HttpMethod.GET,
                new HttpEntity<>(authHeaders(token)), Map.class);
        assertThat(weekly.getBody().get("days_with_data")).isEqualTo(0);

        String path = "/v1/glucose-graphs/by-date/2026-10-01/reprocess";
        var queued = rest.exchange(path, HttpMethod.POST, new HttpEntity<>(authHeaders(token)), Map.class);
        assertThat(queued.getStatusCode()).isEqualTo(HttpStatus.ACCEPTED);
        assertThat(queued.getBody().get("upload_id")).isEqualTo(uploadId.toString());
        UUID reprocessJob = uploadRepository.findById(uploadId).orElseThrow().getParseJobId();
        assertThat(reprocessJob).isNotEqualTo(previousJob);
        rest.exchange(path, HttpMethod.POST, new HttpEntity<>(authHeaders(token)), Map.class);
        assertThat(uploadRepository.findById(uploadId).orElseThrow().getParseJobId()).isEqualTo(reprocessJob);

        mlServiceBody = SUCCESS_BODY;
        runWorkerOnce();
        assertThat(uploadRepository.findById(uploadId).orElseThrow().getParserVersion()).isEqualTo("1.1.5");
        assertThat(readingRepository.findByUploadIdOrderByTimeSlot(uploadId).getFirst().getValue()).isEqualTo(120);
        var fresh = rest.exchange("/v1/glucose-readings/2026-10-01", HttpMethod.GET,
                new HttpEntity<>(authHeaders(token)), Map.class);
        assertThat(fresh.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(fresh.getBody().get("parser_version")).isEqualTo("1.1.5");
        assertThat(fresh.getBody().get("upload_id")).isEqualTo(uploadId.toString());
        assertThat(getStatus(token, uploadId).getBody().get("parser_version")).isEqualTo("1.1.5");
    }

    @Test
    void 재분석_실패시_원본과_기존_행을_보존하고_실패_이유를_구분한다() throws Exception {
        String token = login();
        UUID uploadId = uploadAndComplete(token);
        runWorkerOnce();
        mlServiceStatus = 422;
        mlServiceBody = "{\"code\":\"GRAPH_DATE_NOT_RECOGNIZED\",\"message\":\"날짜 인식 실패\"}";
        var queued = rest.exchange("/v1/glucose-graphs/" + uploadId + "/reprocess", HttpMethod.POST,
                new HttpEntity<>(authHeaders(token)), Map.class);
        assertThat(queued.getStatusCode()).isEqualTo(HttpStatus.ACCEPTED);
        runWorkerOnce();
        assertThat(readingRepository.findByUploadIdOrderByTimeSlot(uploadId)).hasSize(3);
        assertThat(uploadRepository.findById(uploadId)).isPresent();
        var response = getStatus(token, uploadId);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
        assertThat(response.getBody().get("code")).isEqualTo("GRAPH_DATE_NOT_RECOGNIZED");
    }

    @Test
    void 다른_사용자는_원본을_재분석할_수_없다() throws Exception {
        String owner = login();
        UUID uploadId = uploadAndComplete(owner);
        String other = login();
        var response = rest.exchange("/v1/glucose-graphs/" + uploadId + "/reprocess", HttpMethod.POST,
                new HttpEntity<>(authHeaders(other)), Map.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(findJobForUpload(uploadId).getStatus()).isEqualTo(JobStatus.PENDING);
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "GRAPH_PIPELINE_SMOKE_URL", matches = "http://127\\.0\\.0\\.1:[0-9]+")
    void 실제_OCR에서_추출한_96칸이_업로드_DB_시계열_리포트까지_변형없이_이어진다() throws Exception {
        var image = new BufferedImage(1200, 800, BufferedImage.TYPE_INT_RGB);
        var graphics = image.createGraphics();
        graphics.setColor(Color.WHITE);
        graphics.fillRect(0, 0, 1200, 800);
        graphics.setColor(new Color(185, 185, 185));
        for (int y = 220; y <= 700; y += 80) graphics.drawLine(120, y, 1080, y);
        graphics.drawLine(120, 760, 1080, 760);
        graphics.setColor(new Color(20, 20, 20));
        graphics.setFont(new Font(Font.SANS_SERIF, Font.BOLD, 36));
        graphics.drawString("2026-10-01", 350, 86);
        graphics.setStroke(new BasicStroke(4));
        for (int i = 1; i < 96; i++) {
            if (i >= 40 && i <= 48) continue;
            int previousY = (int) Math.round(220 + (350 - (150 + 45 * Math.sin((i-1)/10.0))) / 300 * 480);
            int y = (int) Math.round(220 + (350 - (150 + 45 * Math.sin(i/10.0))) / 300 * 480);
            graphics.drawLine(120 + (i-1)*10, previousY, 120 + i*10, y);
        }
        graphics.dispose();
        var encoded = new ByteArrayOutputStream();
        ImageIO.write(image, "png", encoded);
        forwardToNativeMl = true;
        String token = login();
        UUID uploadId = uploadAndComplete(token, encoded.toByteArray(), "image/png");
        runWorkerOnce();
        assertThat(findJobForUpload(uploadId).getStatus()).isEqualTo(JobStatus.DONE);
        var readings = readingRepository.findByUploadIdOrderByTimeSlot(uploadId);
        assertThat(readings).hasSize(96);
        int count = 0;
        for (int i = 0; i < readings.size(); i++) {
            var reading = readings.get(i);
            assertThat(reading.getTimeSlot()).isEqualTo(i*15);
            if (i >= 40 && i <= 47) {
                assertThat(reading.getValue()).isNull();
                assertThat(reading.getFlag()).isEqualTo(ReadingFlag.MISSING);
            } else {
                count++;
                assertThat(reading.getValue().doubleValue()).isCloseTo(150 + 45*Math.sin(i/10.0),
                        org.assertj.core.data.Offset.offset(2.0));
            }
        }
        var queried = rest.exchange("/v1/glucose-readings/2026-10-01", HttpMethod.GET,
                new HttpEntity<>(authHeaders(token)), Map.class);
        assertThat(queried.getStatusCode()).isEqualTo(HttpStatus.OK);
        List<Map<String, Object>> points = (List<Map<String, Object>>) queried.getBody().get("readings");
        for (int i = 0; i < 96; i++) {
            assertThat(points.get(i).get("value")).isEqualTo(readings.get(i).getValue());
            assertThat(points.get(i).get("flag")).isEqualTo(readings.get(i).getFlag().name());
        }
        var daily = rest.exchange("/v1/reports/daily/2026-10-01", HttpMethod.GET,
                new HttpEntity<>(authHeaders(token)), Map.class);
        assertThat(((Map<?, ?>) daily.getBody().get("glucose")).get("readings_count")).isEqualTo(count);
    }

    private void runWorkerOnce() {
        for (Job job : jobService.claimDueJobs()) {
            jobService.process(job, jobTypeToHandler(job.getType()));
        }
    }

    private JobHandler jobTypeToHandler(String type) {
        return GraphParseJobHandler.JOB_TYPE.equals(type) ? graphParseJobHandler : null;
    }

    private Job findJobForUpload(UUID uploadId) {
        return jobRepository.findAll().stream()
                .filter(j -> j.getType().equals(GraphParseJobHandler.JOB_TYPE) && j.getPayload().contains(uploadId.toString()))
                .reduce((first, second) -> second) // 가장 최근 것
                .orElseThrow(() -> new AssertionError("업로드에 대한 job을 찾지 못함: " + uploadId));
    }

    private String login() {
        ResponseEntity<Map> response = rest.postForEntity(
                "/v1/auth/apple", Map.of("identity_token", "valid:" + UUID.randomUUID()), Map.class);
        return (String) response.getBody().get("access_token");
    }

    private ResponseEntity<Map> getStatus(String accessToken, UUID uploadId) {
        return rest.exchange(
                "/v1/glucose-graphs/" + uploadId,
                HttpMethod.GET,
                new HttpEntity<>(authHeaders(accessToken)),
                Map.class);
    }

    private UUID uploadAndComplete(String accessToken) throws Exception {
        return uploadAndComplete(accessToken, new byte[]{1, 2, 3}, "image/jpeg");
    }

    private UUID uploadAndComplete(String accessToken, byte[] image, String contentType) throws Exception {
        HttpHeaders headers = authHeaders(accessToken);

        ResponseEntity<Map> started = rest.exchange(
                "/v1/glucose-graphs",
                HttpMethod.POST,
                new HttpEntity<>(Map.of("content_type", contentType), headers),
                Map.class);
        String uploadUrl = (String) started.getBody().get("upload_url");
        String uploadId = (String) started.getBody().get("upload_id");

        httpClient.send(
                HttpRequest.newBuilder(URI.create(uploadUrl))
                        .PUT(HttpRequest.BodyPublishers.ofByteArray(image))
                        .header("Content-Type", contentType)
                        .build(),
                HttpResponse.BodyHandlers.discarding());

        ResponseEntity<Void> completed = rest.exchange(
                "/v1/glucose-graphs/" + uploadId + "/complete", HttpMethod.POST, new HttpEntity<>(headers), Void.class);
        assertThat(completed.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);

        return UUID.fromString(uploadId);
    }

    private HttpHeaders authHeaders(String accessToken) {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(accessToken);
        return headers;
    }
}
