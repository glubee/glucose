package com.glucoselog.report;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

import org.junit.jupiter.api.Test;
import com.glucoselog.ml.MlServiceProperties;
import com.sun.net.httpserver.HttpServer;

class ReportNarrationClientTest {
    @Test
    void sends_only_allowed_fact_fields_with_internal_auth_and_fails_closed() throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        var received = new AtomicReference<String>();
        var token = new AtomicReference<String>();
        server.createContext("/v1/report/narrate", exchange -> {
            token.set(exchange.getRequestHeaders().getFirst("X-Internal-Token"));
            received.set(new String(exchange.getRequestBody().readAllBytes(),StandardCharsets.UTF_8));
            byte[] body="{\"paragraphs\":[]}".getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type","application/json");
            exchange.sendResponseHeaders(200,body.length);
            exchange.getResponseBody().write(body);
            exchange.close();
        });
        server.start();
        try {
            var ml = new MlServiceProperties("http://127.0.0.1:"+server.getAddress().getPort(),"synthetic-token",200,200);
            var client = new ReportNarrationClient(ml,new ReportNarrationProperties(true,1000));
            assertThat(client.plan("DAILY",List.of(NarrativeFact.Definition.AVERAGE.fact(138.2))))
                    .contains("paragraphs");
            assertThat(token.get()).isEqualTo("synthetic-token");
            assertThat(received.get()).contains("138.2","average_glucose","DAILY")
                    .doesNotContain("user","date","label","unit");
            assertThat(new ReportNarrationClient(ml,new ReportNarrationProperties(false,1000))
                    .plan("DAILY",List.of())).isNull();
            server.stop(0);
            assertThat(client.plan("DAILY",List.of())).isNull();
        } finally {
            server.stop(0);
        }
    }
}
