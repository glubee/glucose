package com.glucoselog.progress;

import java.util.UUID;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record ProgressOperation(@NotNull UUID id, @NotBlank String kind, String day,
                                Boolean recordOnly, String reason, String end) {}
