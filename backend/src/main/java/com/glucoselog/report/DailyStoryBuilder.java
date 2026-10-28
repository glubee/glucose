package com.glucoselog.report;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Objects;
import java.util.Optional;

import org.springframework.stereotype.Component;

import com.glucoselog.episode.EpisodeProperties;
import com.glucoselog.episode.GlucoseSample;
import com.glucoselog.photo.PhotoContext;

/**
 * 하루 이야기: 그날 기록과 그래프에서 읽힌 값을 시간순 한 문단으로 쓴다(docs/report-story-and-guidance-plan.md 1장).
 * AI 없이 고정 문장 틀만 쓴다. 시간 순서의 변화만 쓰고, 기록이 수치를 바꿨다고(원인) 말하지 않는다.
 * 숫자는 모두 여기서 계산한 읽힌 값이고, 끊긴 구간은 보간하지 않고 "알 수 없다"고 쓴다.
 */
@Component
public class DailyStoryBuilder {

    private static final ZoneId KST = ZoneId.of("Asia/Seoul");
    /** 먹기 전 값으로 보는 범위 */
    private static final Duration BASELINE_LOOKBACK = Duration.ofMinutes(30);
    /** 처치 전 낮은 값을 찾는 범위 */
    private static final Duration LOW_LOOKBACK = Duration.ofMinutes(45);
    /** 식사·간식 뒤 변화를 보는 최대 시간(분석 창보다 짧게: 문장은 직후 흐름만) */
    private static final Duration MEAL_FOLLOW = Duration.ofHours(3);
    /** 인슐린 기록을 식사 장면에 함께 쓰는 범위 */
    private static final Duration INSULIN_ATTACH = Duration.ofMinutes(30);
    /** 이보다 긴 빈 구간만 문장으로 쓴다 */
    private static final Duration GAP_MENTION = Duration.ofHours(2);
    private static final int MEANINGFUL_RISE = 10;
    private static final int MEANINGFUL_FALL = 15;

    private final EpisodeProperties episodeProperties;

    public DailyStoryBuilder(EpisodeProperties episodeProperties) {
        this.episodeProperties = episodeProperties;
    }

    private record Scene(Instant time, List<String> sentences) {
    }

    public List<String> build(List<GlucoseSample> samples, List<EpisodeSummary> episodes,
            List<DailyReportResponse.InsulinEventMarker> insulinEvents) {
        List<GlucoseSample> readings = samples == null ? List.of() : samples.stream()
                .sorted(Comparator.comparing(GlucoseSample::time)).toList();
        List<GlucoseSample> values = readings.stream().filter(s -> s.value() != null).toList();
        List<EpisodeSummary> sorted = episodes.stream().sorted(Comparator.comparing(EpisodeSummary::startAt)).toList();

        List<String> lines = new ArrayList<>();
        if (values.isEmpty()) {
            lines.add(sorted.isEmpty() && insulinEvents.isEmpty()
                    ? "이 날은 혈당 그래프도, 음식·인슐린 기록도 없어요."
                    : "이 날은 혈당 그래프가 없어 남긴 기록만 정리했어요.");
        } else {
            int min = values.stream().mapToInt(GlucoseSample::value).min().orElseThrow();
            int max = values.stream().mapToInt(GlucoseSample::value).max().orElseThrow();
            lines.add("이 날 그래프에서 읽힌 값은 최저 " + min + ", 최고 " + max + endCopula(max));
            if (sorted.isEmpty() && insulinEvents.isEmpty()) {
                lines.add("남긴 음식·인슐린 기록은 없어요.");
            }
        }

        List<Scene> scenes = new ArrayList<>();
        List<DailyReportResponse.InsulinEventMarker> attached = new ArrayList<>();
        for (int i = 0; i < sorted.size(); i++) {
            EpisodeSummary episode = sorted.get(i);
            Instant nextStart = i + 1 < sorted.size() ? sorted.get(i + 1).startAt() : null;
            List<DailyReportResponse.InsulinEventMarker> nearby = insulinEvents.stream()
                    .filter(event -> !attached.contains(event))
                    .filter(event -> Math.abs(Duration.between(episode.startAt(), event.occurredAt()).toMinutes())
                            <= INSULIN_ATTACH.toMinutes())
                    .toList();
            attached.addAll(nearby);
            scenes.add(episodeScene(episode, nextStart, nearby, values));
        }
        for (DailyReportResponse.InsulinEventMarker event : insulinEvents) {
            if (!attached.contains(event)) {
                scenes.add(new Scene(event.occurredAt(), List.of(time(event.occurredAt()) + "에 " + insulin(event) + "를 기록했어요.")));
            }
        }
        scenes.addAll(lowScenes(values, sorted));
        scenes.addAll(gapScenes(readings));
        scenes.sort(Comparator.comparing(Scene::time));
        scenes.forEach(scene -> lines.addAll(scene.sentences()));
        return lines;
    }

    // MARK: 장면

    private Scene episodeScene(EpisodeSummary episode, Instant nextStart,
            List<DailyReportResponse.InsulinEventMarker> insulin, List<GlucoseSample> values) {
        Instant start = episode.startAt();
        List<String> sentences = new ArrayList<>();
        String what = episode.foods().isEmpty() ? null : String.join(", ", episode.foods());
        String insulinPart = insulin.stream()
                .map(event -> time(event.occurredAt()) + "에 " + insulin(event) + "를 기록했")
                .reduce((a, b) -> a + "고, " + b).map(text -> text + "고, ").orElse("");

        if (episode.effectiveContext() == PhotoContext.HYPO_TREATMENT) {
            Optional<GlucoseSample> low = minBetween(values, start.minus(LOW_LOOKBACK), start)
                    .filter(sample -> sample.value() < episodeProperties.hypoGlucoseThreshold());
            String food = what == null ? "저혈당 대응 음식" : what;
            if (low.isPresent()) {
                sentences.add(insulinPart + time(low.get().time()) + "쯤 혈당이 " + low.get().value() + "까지 읽혀 "
                        + time(start) + "에 " + food + object(food) + " 먹었어요.");
            } else {
                sentences.add(insulinPart + time(start) + "에 저혈당 대응으로 " + food + object(food) + " 먹었어요.");
            }
            if (Boolean.TRUE.equals(episode.autoReclassified())) {
                sentences.add("기록할 때는 " + ReportSummaryBuilder.label(episode.originalContext())
                        + "으로 남겼지만, 직전에 읽힌 값이 낮아 저혈당 대응으로 정리했어요.");
            }
            sentences.add(afterTreatment(start, values));
            return new Scene(start, sentences);
        }

        String verb = episode.effectiveContext() == PhotoContext.ALCOHOL ? "마셨어요" : "먹었어요";
        if (what == null) {
            sentences.add(insulinPart + time(start) + "에 " + ReportSummaryBuilder.label(episode.effectiveContext()) + " 기록이 있어요.");
        } else {
            sentences.add(insulinPart + time(start) + "에 " + what + object(what) + " " + verb + ".");
        }

        if (values.isEmpty()) {
            return new Scene(start, sentences);
        }
        if (episode.effectiveContext() == PhotoContext.ALCOHOL) {
            Instant until = start.plus(Duration.ofHours(episodeProperties.alcoholWindowHours()));
            minBetween(values, start.plusSeconds(1), until)
                    .filter(sample -> sample.value() < episodeProperties.hypoGlucoseThreshold())
                    .ifPresent(low -> sentences.add("그 뒤 " + time(low.time()) + "쯤 " + low.value()
                            + "까지 낮은 값이 읽혔어요."));
            return new Scene(start, sentences);
        }

        Instant followEnd = start.plus(MEAL_FOLLOW);
        boolean cut = nextStart != null && nextStart.isBefore(followEnd);
        if (cut) {
            followEnd = nextStart;
        }
        Optional<GlucoseSample> baseline = lastBetween(values, start.minus(BASELINE_LOOKBACK), start);
        Optional<GlucoseSample> peak = maxBetween(values, start.plusSeconds(1), followEnd);
        if (peak.isEmpty()) {
            sentences.add("먹은 뒤 구간은 그래프가 비어 있어 알 수 없어요.");
            return new Scene(start, sentences);
        }
        GlucoseSample top = peak.get();
        String after = duration(Duration.between(start, top.time()));
        if (baseline.isPresent() && top.value() - baseline.get().value() >= MEANINGFUL_RISE) {
            int before = baseline.get().value();
            StringBuilder line = new StringBuilder("먹기 전 " + before + adjectiveCopula(before) + " 혈당은 " + after + " 뒤 "
                    + top.value() + direction(top.value()) + " 가장 높았");
            Optional<GlucoseSample> end = lastBetween(values, top.time().plusSeconds(1), followEnd)
                    .filter(sample -> top.value() - sample.value() >= MEANINGFUL_FALL);
            if (end.isPresent()) {
                line.append("고, ").append(time(end.get().time())).append("쯤 ").append(end.get().value())
                        .append(direction(end.get().value())).append(" 내려왔어요.");
            } else {
                line.append("어요.");
            }
            sentences.add(line.toString());
        } else if (baseline.isPresent()) {
            int low = minBetween(values, start, followEnd).map(GlucoseSample::value).orElse(baseline.get().value());
            sentences.add("먹은 뒤 " + duration(Duration.between(start, followEnd)) + " 동안은 " + low + "~" + top.value()
                    + " 사이에서 크게 오르지 않았어요.");
        } else {
            sentences.add("먹기 직전 값은 비어 있고, 먹은 뒤 " + after + " 지나 가장 높은 " + top.value() + " mg/dL가 읽혔어요.");
        }
        if (cut && Duration.between(start, nextStart).compareTo(Duration.ofMinutes(90)) < 0) {
            sentences.add("바로 다음 기록과 시간이 가까워 이 기록만의 흐름으로 보기는 어려워요.");
        }
        return new Scene(start, sentences);
    }

    private String afterTreatment(Instant start, List<GlucoseSample> values) {
        Instant end = start.plus(Duration.ofHours(episodeProperties.hypoTreatmentWindowHours()));
        long hours = episodeProperties.hypoTreatmentWindowHours();
        List<GlucoseSample> window = between(values, start.plusSeconds(1), end);
        if (window.isEmpty()) {
            return "그 뒤 " + hours + "시간은 그래프가 비어 있어 알 수 없어요.";
        }
        int threshold = episodeProperties.reboundGlucoseThreshold();
        StringBuilder line = new StringBuilder("그 뒤 ");
        window.stream().filter(sample -> sample.value() >= episodeProperties.hypoGlucoseThreshold()).findFirst()
                .ifPresent(up -> line.append(duration(Duration.between(start, up.time()))).append(" 만에 ")
                        .append(up.value()).append(direction(up.value())).append(" 올라왔고, "));
        GlucoseSample top = window.stream().max(Comparator.comparing(GlucoseSample::value)).orElseThrow();
        if (top.value() > threshold) {
            line.append(hours).append("시간 안에 ").append(top.value()).append("까지 읽혔어요.");
        } else {
            line.append(hours).append("시간 동안 ").append(threshold).append(objectNumber(threshold)).append(" 넘는 값은 없었어요.");
        }
        return line.toString();
    }

    /** 처치 기록 직전이 아닌 낮은 값(70 미만이 이어진 구간마다 가장 낮은 값 하나) */
    private List<Scene> lowScenes(List<GlucoseSample> values, List<EpisodeSummary> episodes) {
        List<Scene> scenes = new ArrayList<>();
        int threshold = episodeProperties.hypoGlucoseThreshold();
        GlucoseSample runMin = null;
        for (GlucoseSample sample : values) {
            if (sample.value() < threshold) {
                if (runMin == null || sample.value() < runMin.value()) runMin = sample;
            } else if (runMin != null) {
                addLow(scenes, runMin, episodes);
                runMin = null;
            }
        }
        if (runMin != null) addLow(scenes, runMin, episodes);
        return scenes;
    }

    private void addLow(List<Scene> scenes, GlucoseSample low, List<EpisodeSummary> episodes) {
        boolean explained = episodes.stream().anyMatch(episode ->
                (episode.effectiveContext() == PhotoContext.HYPO_TREATMENT
                        && !low.time().isAfter(episode.startAt())
                        && !low.time().isBefore(episode.startAt().minus(LOW_LOOKBACK)))
                || (episode.effectiveContext() == PhotoContext.ALCOHOL && low.time().isAfter(episode.startAt())
                        && low.time().isBefore(episode.startAt().plus(Duration.ofHours(episodeProperties.alcoholWindowHours())))));
        if (!explained) {
            scenes.add(new Scene(low.time(), List.of(time(low.time()) + "쯤 혈당이 " + low.value() + "까지 낮게 읽혔어요.")));
        }
    }

    private List<Scene> gapScenes(List<GlucoseSample> readings) {
        List<Scene> scenes = new ArrayList<>();
        Instant gapStart = null;
        Instant lastMissing = null;
        for (GlucoseSample sample : readings) {
            if (sample.value() == null) {
                if (gapStart == null) gapStart = sample.time();
                lastMissing = sample.time();
            } else if (gapStart != null) {
                addGap(scenes, gapStart, sample.time());
                gapStart = null;
            }
        }
        if (gapStart != null) addGap(scenes, gapStart, lastMissing.plus(Duration.ofMinutes(15)));
        return scenes;
    }

    private static void addGap(List<Scene> scenes, Instant from, Instant to) {
        if (Duration.between(from, to).compareTo(GAP_MENTION) >= 0) {
            scenes.add(new Scene(from, List.of(time(from) + "부터 " + time(to) + "까지는 그래프가 비어 있어 이 구간은 알 수 없어요.")));
        }
    }

    // MARK: 값 찾기

    private static List<GlucoseSample> between(List<GlucoseSample> values, Instant from, Instant to) {
        return values.stream().filter(s -> !s.time().isBefore(from) && !s.time().isAfter(to)).toList();
    }

    private static Optional<GlucoseSample> lastBetween(List<GlucoseSample> values, Instant from, Instant to) {
        List<GlucoseSample> found = between(values, from, to);
        return found.isEmpty() ? Optional.empty() : Optional.of(found.get(found.size() - 1));
    }

    private static Optional<GlucoseSample> maxBetween(List<GlucoseSample> values, Instant from, Instant to) {
        return between(values, from, to).stream().max(Comparator.comparing(GlucoseSample::value));
    }

    private static Optional<GlucoseSample> minBetween(List<GlucoseSample> values, Instant from, Instant to) {
        return between(values, from, to).stream().min(Comparator.comparing(GlucoseSample::value));
    }

    // MARK: 말 만들기

    /** "오전 8시 10분", "오후 1시", "밤 12시" */
    static String time(Instant instant) {
        ZonedDateTime t = instant.atZone(KST);
        int hour = t.getHour();
        String prefix = hour == 0 ? "밤 12" : hour < 12 ? "오전 " + hour : hour == 12 ? "낮 12" : "오후 " + (hour - 12);
        return prefix + "시" + (t.getMinute() == 0 ? "" : " " + t.getMinute() + "분");
    }

    /** "40분", "1시간", "1시간 40분" */
    static String duration(Duration duration) {
        long minutes = Math.max(0, duration.toMinutes());
        long h = minutes / 60;
        long m = minutes % 60;
        if (h == 0) return m + "분";
        return h + "시간" + (m == 0 ? "" : " " + m + "분");
    }

    private static String insulin(DailyReportResponse.InsulinEventMarker event) {
        BigDecimal units = event.units().stripTrailingZeros();
        String kind = Objects.requireNonNullElse(event.kind(), "").isBlank() ? "인슐린" : event.kind().trim();
        return kind + " " + units.toPlainString() + "단위";
    }

    /** 마지막 글자에 받침이 있는지(숫자는 한국어로 읽은 소리 기준: 1·7·8은 ㄹ) */
    static Character lastSound(String word) {
        String trimmed = word.trim();
        if (trimmed.isEmpty()) return null;
        char last = trimmed.charAt(trimmed.length() - 1);
        if (last >= '가' && last <= '힣') {
            int jong = (last - '가') % 28;
            return jong == 0 ? null : (jong == 8 ? 'ㄹ' : 'O');
        }
        if (Character.isDigit(last)) {
            return switch (last) {
                case '1', '7', '8' -> 'ㄹ';
                case '2', '4', '5', '9' -> null;
                default -> 'O'; // 0(영·십·백), 3(삼), 6(육)
            };
        }
        return null;
    }

    private static String object(String word) {
        return lastSound(word) == null ? "를" : "을";
    }

    private static String objectNumber(int number) {
        return lastSound(String.valueOf(number)) == null ? "를" : "을";
    }

    /** "168로", "120으로" */
    private static String direction(int number) {
        Character sound = lastSound(String.valueOf(number));
        return sound == null || sound == 'ㄹ' ? "로" : "으로";
    }

    /** "120이었어요." / "105였어요." */
    private static String endCopula(int number) {
        return lastSound(String.valueOf(number)) == null ? "였어요." : "이었어요.";
    }

    /** "105였던", "168이었던" — 이어지는 말 앞 */
    private static String adjectiveCopula(int number) {
        return lastSound(String.valueOf(number)) == null ? "였던" : "이었던";
    }

}
