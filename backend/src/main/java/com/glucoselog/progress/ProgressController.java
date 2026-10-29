package com.glucoselog.progress;

import java.util.List;
import java.util.UUID;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController @RequestMapping("/v1/progress")
public class ProgressController {
    private final ProgressSyncService service;
    public ProgressController(ProgressSyncService service) { this.service = service; }
    public record Request(DayCloseState legacyState, @NotNull @Size(max = 100) List<@Valid ProgressOperation> operations) {}
    @GetMapping
    public ProgressSyncService.Response read(Authentication auth) { return service.read((UUID) auth.getPrincipal()); }
    @PostMapping("/sync")
    public ProgressSyncService.Response sync(@Valid @RequestBody Request request, Authentication auth) {
        return service.sync((UUID) auth.getPrincipal(), request.legacyState(), request.operations());
    }
}
