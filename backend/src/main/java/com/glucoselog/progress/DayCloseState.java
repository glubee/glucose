package com.glucoselog.progress;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Set;
import java.util.TreeSet;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/** 완료 행동의 상태만 계산한다. 혈당 수치/치료 판단은 사용하지 않는다. */
@JsonIgnoreProperties(ignoreUnknown = true)
public class DayCloseState {
    public Set<String> closedDays = new TreeSet<>();
    public Set<String> recordOnlyDays = new TreeSet<>();
    public Set<String> honeypotSavedDays = new TreeSet<>();
    public int honeypots;
    public Rest rest;
    public String lastHoneypotUse;

    public record Rest(String reason, String start, String end) {}

    public boolean hasData() {
        return !closedDays.isEmpty() || !honeypotSavedDays.isEmpty() || honeypots > 0 || rest != null;
    }

    public void validate(LocalDate today) {
        if (closedDays == null || recordOnlyDays == null || honeypotSavedDays == null
                || closedDays.size() > 40000 || honeypotSavedDays.size() > 40000
                || honeypots < 0 || honeypots > 2 || !closedDays.containsAll(recordOnlyDays)) invalid();
        for (String day : closedDays) validPastDate(day, today);
        for (String day : honeypotSavedDays) {
            validPastDate(day, today);
            if (closedDays.contains(day)) invalid();
        }
        if (lastHoneypotUse != null) validPastDate(lastHoneypotUse, today);
        if (rest != null) {
            validPastDate(rest.start(), today);
            validateRest(rest.reason(), rest.start(), rest.end());
        }
    }

    public void mergeHistory(DayCloseState legacy) {
        for (String day : legacy.closedDays) {
            boolean existed = closedDays.contains(day);
            closedDays.add(day);
            if (!legacy.recordOnlyDays.contains(day)) recordOnlyDays.remove(day);
            else if (!existed) recordOnlyDays.add(day);
        }
        honeypotSavedDays.addAll(legacy.honeypotSavedDays);
        honeypotSavedDays.removeAll(closedDays);
    }

    public void apply(ProgressOperation operation, LocalDateTime now) {
        LocalDate today = now.toLocalDate();
        switch (operation.kind()) {
            case "close_day" -> {
                LocalDate day = validPastDate(operation.day(), today);
                String key = day.toString();
                int earnedBefore = milestoneCount();
                boolean first = closedDays.add(key);
                honeypotSavedDays.remove(key);
                if (!Boolean.TRUE.equals(operation.recordOnly())) recordOnlyDays.remove(key);
                else if (first) recordOnlyDays.add(key);
                honeypots = Math.min(2, honeypots + Math.max(0, milestoneCount() - earnedBefore));
            }
            case "start_rest" -> {
                validPastDate(operation.day(), today);
                validateRest(operation.reason(), operation.day(), operation.end());
                rest = new Rest(operation.reason(), operation.day(), operation.end());
            }
            case "end_rest" -> {
                LocalDate day = validPastDate(operation.day(), today);
                if (rest != null) {
                    LocalDate yesterday = day.minusDays(1);
                    rest = yesterday.isBefore(LocalDate.parse(rest.start())) ? null
                            : new Rest(rest.reason(), rest.start(), yesterday.toString());
                }
            }
            case "apply_honeypots" -> applyHoneypots(now);
            default -> invalid();
        }
    }

    public int streak(LocalDate day) {
        LocalDate cursor = closedDays.contains(day.toString()) ? day : day.minusDays(1);
        int count = 0;
        for (int i = 0; i < 366; i++, cursor = cursor.minusDays(1)) {
            if (closedDays.contains(cursor.toString())) count++;
            else if (!bridges(cursor)) break;
        }
        return count;
    }

    public void applyHoneypots(LocalDateTime now) {
        if (honeypots == 0) return;
        LocalDate last = now.toLocalDate().minusDays(now.getHour() < 12 ? 2 : 1);
        java.util.List<LocalDate> missed = new java.util.ArrayList<>();
        for (int i = 0; i < 14; i++, last = last.minusDays(1)) {
            if (closedDays.contains(last.toString()) || bridges(last)) break;
            missed.add(0, last);
        }
        if (missed.isEmpty() || streak(missed.get(0).minusDays(1)) == 0) return;
        for (LocalDate day : missed) {
            if (honeypots == 0) break;
            honeypotSavedDays.add(day.toString());
            lastHoneypotUse = day.toString();
            honeypots--;
        }
    }

    private boolean bridges(LocalDate day) {
        String key = day.toString();
        return honeypotSavedDays.contains(key) || (rest != null
                && key.compareTo(rest.start()) >= 0 && key.compareTo(rest.end()) <= 0);
    }

    /** 완료 도착 순서와 무관하게 각 연속 구간의 7일 경계를 한 번씩만 센다. */
    private int milestoneCount() {
        int run = 0, total = 0;
        LocalDate previous = null;
        for (String key : new TreeSet<>(closedDays)) {
            LocalDate day = LocalDate.parse(key);
            if (previous != null) {
                for (LocalDate gap = previous.plusDays(1); gap.isBefore(day); gap = gap.plusDays(1)) {
                    if (!bridges(gap)) { run = 0; break; }
                }
            }
            run++;
            if (run % 7 == 0) total++;
            previous = day;
        }
        return total;
    }

    private static LocalDate validPastDate(String value, LocalDate today) {
        if (value == null) invalid();
        LocalDate day = LocalDate.parse(value);
        if (day.isBefore(LocalDate.of(1900, 1, 1)) || day.isAfter(today)) invalid();
        return day;
    }

    private static void validateRest(String reason, String start, String end) {
        if (reason == null || start == null || end == null
                || !Set.of("resting", "unwell", "noSensor").contains(reason)) invalid();
        LocalDate first = LocalDate.parse(start), last = LocalDate.parse(end);
        if (last.isBefore(first) || last.isAfter(first.plusDays(365))) invalid();
    }

    private static void invalid() { throw new IllegalArgumentException("invalid progress state"); }
}
