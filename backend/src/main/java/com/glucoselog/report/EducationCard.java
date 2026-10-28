package com.glucoselog.report;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "education_card")
public class EducationCard {

    @Id
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "trigger")
    private EducationCardTrigger trigger;

    @Column(nullable = false, unique = true)
    private String code;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private EducationCardPlacement placement;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(nullable = false, columnDefinition = "jsonb")
    private List<EducationCardSource> sources;

    @Column(nullable = false)
    private boolean approved;

    @Column(name = "reviewed_by")
    private String reviewedBy;

    @Column(name = "reviewed_at")
    private LocalDate reviewedAt;

    @Column(name = "review_type")
    private String reviewType;

    @Column(nullable = false)
    private String title;

    @Column(nullable = false)
    private String body;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected EducationCard() {
    }

    public UUID getId() {
        return id;
    }

    public String getCode() { return code; }
    public List<EducationCardSource> getSources() { return sources; }
    public String getReviewedBy() { return reviewedBy; }
    public LocalDate getReviewedAt() { return reviewedAt; }
    public String getReviewType() { return reviewType; }

    public EducationCardTrigger getTrigger() {
        return trigger;
    }

    public String getTitle() {
        return title;
    }

    public String getBody() {
        return body;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
