package com.glucoselog.progress;

import java.util.UUID;
import jakarta.persistence.*;

@Entity @Table(name = "progress_account")
public class ProgressAccount {
    @Id @Column(name = "user_id") private UUID userId;
    @Column(name = "state_json", nullable = false, columnDefinition = "text") private String stateJson;
    @Column(nullable = false) private boolean initialized;
    @Column(nullable = false) private long revision;
    protected ProgressAccount() {}
    public String getStateJson() { return stateJson; }
    public long getRevision() { return revision; }
    public boolean isInitialized() { return initialized; }
    public void replace(String json, boolean initialized) {
        stateJson = json; this.initialized = initialized; revision++;
    }
}
