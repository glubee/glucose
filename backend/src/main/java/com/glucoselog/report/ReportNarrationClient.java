package com.glucoselog.report;

import java.math.BigDecimal;
import java.time.Duration;
import java.util.List;
import java.util.UUID;

import org.springframework.boot.http.client.ClientHttpRequestFactoryBuilder;
import org.springframework.boot.http.client.ClientHttpRequestFactorySettings;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import com.glucoselog.ml.MlServiceProperties;

@Component
public class ReportNarrationClient {
    private final RestClient client;
    private final MlServiceProperties ml;
    private final ReportNarrationProperties properties;

    public ReportNarrationClient(MlServiceProperties ml, ReportNarrationProperties properties) {
        this.ml = ml;
        this.properties = properties;
        var settings = ClientHttpRequestFactorySettings.defaults()
                .withConnectTimeout(Duration.ofMillis(ml.connectTimeoutMs()))
                .withReadTimeout(Duration.ofMillis(Math.max(1, properties.timeoutMs())));
        client = RestClient.builder().baseUrl(ml.serviceUrl())
                .requestFactory(ClientHttpRequestFactoryBuilder.detect().build(settings)).build();
    }

    /** 오류 시 null을 반환한다. 외부 응답 본문이나 건강 수치를 로그에 남기지 않는다. */
    public String plan(String kind, List<NarrativeFact> facts) {
        if (!properties.enabled()) {
            return null;
        }
        try {
            return client.post().uri("/v1/report/narrate")
                    .header("X-Internal-Token", ml.internalToken())
                    .header("X-Request-Id", UUID.randomUUID().toString())
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(new Request(kind, facts.stream().map(fact -> new InputFact(fact.id(), fact.value())).toList()))
                    .retrieve().body(String.class);
        } catch (RuntimeException error) {
            // Optional narration must never break the factual report or log provider bodies.
            return null;
        }
    }

    private record InputFact(String id, BigDecimal value) {}
    private record Request(String kind, List<InputFact> facts) {}
}
