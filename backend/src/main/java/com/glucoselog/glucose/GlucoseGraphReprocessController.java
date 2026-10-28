package com.glucoselog.glucose;

import java.time.LocalDate;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/v1/glucose-graphs")
public class GlucoseGraphReprocessController {
    private final GlucoseGraphReprocessService service;

    public GlucoseGraphReprocessController(GlucoseGraphReprocessService service) { this.service = service; }

    @PostMapping("/{uploadId}/reprocess")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public GlucoseGraphReprocessService.Response byId(@PathVariable UUID uploadId, Authentication authentication) {
        return service.byId((UUID) authentication.getPrincipal(), uploadId);
    }

    @PostMapping("/by-date/{date}/reprocess")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public GlucoseGraphReprocessService.Response byDate(@PathVariable LocalDate date, Authentication authentication) {
        return service.byDate((UUID) authentication.getPrincipal(), date);
    }
}
