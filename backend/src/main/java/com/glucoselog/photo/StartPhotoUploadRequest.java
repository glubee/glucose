package com.glucoselog.photo;

import jakarta.validation.constraints.NotBlank;
import java.time.Instant;
import java.util.UUID;

public record StartPhotoUploadRequest(@NotBlank String contentType, PhotoContext context, Instant capturedAt, UUID clientId) {
}
