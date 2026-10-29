package com.glucoselog.photo;
import java.time.Instant;
import java.util.UUID;
import jakarta.validation.constraints.NotNull;
public record PhotoMetadataRequest(@NotNull Instant capturedAt, UUID clientId, PhotoContext context) {}
