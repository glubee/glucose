package com.glucoselog.photo;
import java.time.Instant;
import java.util.UUID;
public record PhotoMetadata(UUID photoId, UUID clientId, Instant capturedAt, PhotoContext context,
                            PhotoStatus status, boolean confirmed, boolean dismissed) {
    public static PhotoMetadata from(IntakePhoto photo) {
        return new PhotoMetadata(photo.getId(), photo.getClientId(), photo.getCapturedAt(),
                photo.getContext() == null ? PhotoContext.MEAL : photo.getContext(),
                photo.getStatus(), photo.isConfirmed(), photo.isDismissed());
    }
}
