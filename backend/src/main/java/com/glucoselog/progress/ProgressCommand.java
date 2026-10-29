package com.glucoselog.progress;

import java.time.Instant;
import java.util.UUID;
import jakarta.persistence.*;

@Entity @Table(name = "progress_command")
public class ProgressCommand {
    @Id private UUID id;
    @Column(name = "user_id", nullable = false) private UUID userId;
    @Column(name = "operation_id", nullable = false) private UUID operationId;
    @Column(name = "payload_hash", nullable = false, length = 64) private String payloadHash;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    protected ProgressCommand() {}
    public ProgressCommand(UUID userId, UUID operationId, String hash) {
        id = UUID.randomUUID(); this.userId = userId; this.operationId = operationId;
        payloadHash = hash; createdAt = Instant.now();
    }
    public String getPayloadHash() { return payloadHash; }
}
