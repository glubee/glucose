package com.glucoselog.report;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import com.glucoselog.photo.PhotoContext;

public record FoodObservationResponse(
        String kind, LocalDate from, LocalDate to, int intervalMinutes,
        List<Observation> observations, List<RepeatedFood> repeatedFoods, List<String> limitations) {
    public record Food(String name, Integer count, String unit) {}
    public record Reading(Instant time, int value) {}
    public record Observation(
            UUID intakeId, Instant occurredAt, PhotoContext context, List<Food> foods,
            Instant windowEndAt, int windowMinutes, String status,
            Reading baseline, Reading peak, Integer peakDelta, Reading endReading, Integer endDelta,
            int readingsCount, int expectedReadingsCount, BigDecimal coverageRatio, int clippedReadingsCount,
            List<UUID> overlappingIntakeIds, int insulinEventsCount, boolean comparable,
            List<String> reasonCodes, List<String> notes, String summary) {}
    public record RepeatedFood(
            String id, PhotoContext context, List<Food> foods,
            int recordsCount, int comparableCount, int comparisonDays, int insulinAccompaniedCount,
            boolean amountUnknown, BigDecimal meanPeakDelta, Integer minPeakDelta, Integer maxPeakDelta,
            List<UUID> intakeIds, List<UUID> comparableIntakeIds, String summary) {}
}
