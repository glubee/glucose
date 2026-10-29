package com.glucoselog.photo;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "intake_photo")
public class IntakePhoto {

    @Id
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "object_key", nullable = false, unique = true)
    private String objectKey;

    @Column(name = "content_type", nullable = false)
    private String contentType;

    @Enumerated(EnumType.STRING)
    @Column(name = "context")
    private PhotoContext context;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private PhotoStatus status;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "uploaded_at")
    private Instant uploadedAt;

    @Column(name = "recognition_job_id")
    private UUID recognitionJobId;

    @Column(name = "captured_at") private Instant capturedAt;
    @Column(name = "client_id") private UUID clientId;
    @Column(name = "confirmed_at") private Instant confirmedAt;
    @Column(name = "dismissed_at") private Instant dismissedAt;

    protected IntakePhoto() {
    }

    public IntakePhoto(UUID userId, String objectKey, String contentType, PhotoContext context) {
        this.id = UUID.randomUUID();
        this.userId = userId;
        this.objectKey = objectKey;
        this.contentType = contentType;
        this.context = context;
        this.status = PhotoStatus.PENDING_UPLOAD;
        this.createdAt = Instant.now();
    }

    public void markUploaded(Instant now) {
        this.status = PhotoStatus.UPLOADED;
        this.uploadedAt = now;
    }

    public void setRecognitionJobId(UUID recognitionJobId) {
        this.recognitionJobId = recognitionJobId;
    }

    public UUID getId() {
        return id;
    }

    public UUID getUserId() {
        return userId;
    }

    public String getObjectKey() {
        return objectKey;
    }

    public String getContentType() {
        return contentType;
    }

    public PhotoContext getContext() {
        return context;
    }

    public PhotoStatus getStatus() {
        return status;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUploadedAt() {
        return uploadedAt;
    }

    public UUID getRecognitionJobId() {
        return recognitionJobId;
    }

    public Instant getCapturedAt() { return capturedAt == null ? createdAt : capturedAt; }
    public UUID getClientId() { return clientId; }
    public boolean isConfirmed() { return confirmedAt != null; }
    public boolean isDismissed() { return dismissedAt != null; }
    public void confirm() { if (confirmedAt == null) confirmedAt = Instant.now(); }
    public void dismiss() { if (dismissedAt == null) dismissedAt = Instant.now(); }
    public void restoreMetadata(Instant capture, UUID client, PhotoContext context) {
        if (capturedAt == null && capture != null) capturedAt = capture;
        if (clientId == null && client != null) clientId = client;
        if (context != null && !isConfirmed() && !isDismissed()) this.context = context;
    }
}
