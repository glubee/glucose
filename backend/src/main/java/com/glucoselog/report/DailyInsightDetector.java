package com.glucoselog.report;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.glucoselog.episode.EpisodeProperties;
import com.glucoselog.episode.GlucoseSample;
import com.glucoselog.photo.PhotoContext;

/**
 * 흐름 안내: 그래프 모양과 기록을 코드 규칙으로 찾아, 미리 써 둔 일반 안내를 붙인다(docs/report-story-and-guidance-plan.md 1-4).
 * 진단이 아니라 "이런 흐름은 ~일 가능성이 알려져 있어요" + 출처 + "반복되면 의료진과 확인"까지만 말한다.
 * 의료인 검토 전 문구라 reviewStatus=DRAFT로 내보내고, report.insights-enabled가 켜졌을 때만 만든다(기본 꺼짐).
 * 용량은 말하지 않는다. 일반 지침의 숫자(15g, 15분)는 결정 2에 따라 쓴다.
 */
@Component
public class DailyInsightDetector {

    private static final ZoneId KST = ZoneId.of("Asia/Seoul");
    private static final int MAX_INSIGHTS = 3;

    static final ReportInsight.Source ADA_MORNING = new ReportInsight.Source(
            "미국당뇨병학회(ADA) · 아침 고혈당", "https://diabetes.org/living-with-diabetes/high-morning-blood-glucose");
    static final ReportInsight.Source MAYO_DAWN = new ReportInsight.Source(
            "Mayo Clinic · 새벽 현상", "https://www.mayoclinic.org/diseases-conditions/diabetes/expert-answers/dawn-effect/faq-20057937");
    static final ReportInsight.Source ADA_HYPER = new ReportInsight.Source(
            "미국당뇨병학회(ADA) · 고혈당", "https://diabetes.org/living-with-diabetes/treatment-care/hyperglycemia");
    static final ReportInsight.Source BELL_2015 = new ReportInsight.Source(
            "Bell 외, Diabetes Care 2015 · 지방·단백질과 식후 혈당", "https://pubmed.ncbi.nlm.nih.gov/25998293/");
    static final ReportInsight.Source ADA_ALCOHOL = new ReportInsight.Source(
            "미국당뇨병학회(ADA) · 술과 당뇨병", "https://diabetes.org/health-wellness/alcohol-and-diabetes");
    static final ReportInsight.Source ADA_HYPO = new ReportInsight.Source(
            "미국당뇨병학회(ADA) · 저혈당", "https://diabetes.org/living-with-diabetes/hypoglycemia-low-blood-glucose");

    private final EpisodeProperties properties;
    private final boolean enabled;

    public DailyInsightDetector(EpisodeProperties properties,
            @Value("${report.insights-enabled:false}") boolean enabled) {
        this.properties = properties;
        this.enabled = enabled;
    }

    /**
     * @param previousDayEpisodes 전날 기록(밤 술 뒤 아침 낮은 값을 보려고). 없으면 빈 목록
     */
    public boolean isEnabled() {
        return enabled;
    }

    public List<ReportInsight> detect(LocalDate date, List<GlucoseSample> samples, List<EpisodeSummary> episodes,
            List<EpisodeSummary> previousDayEpisodes, List<DailyReportResponse.InsulinEventMarker> insulinEvents) {
        if (!enabled || samples == null) return List.of();
        List<GlucoseSample> values = samples.stream().filter(s -> s.value() != null)
                .sorted(Comparator.comparing(GlucoseSample::time)).toList();
        if (values.size() < 8) return List.of();
        List<EpisodeSummary> sorted = episodes.stream().sorted(Comparator.comparing(EpisodeSummary::startAt)).toList();

        List<ReportInsight> found = new ArrayList<>();
        alcoholLateLow(values, sorted, previousDayEpisodes).ifPresent(found::add);
        for (EpisodeSummary episode : sorted) {
            if (episode.effectiveContext() == PhotoContext.HYPO_TREATMENT) {
                slowTreatment(episode, values).ifPresent(found::add);
                treatmentRebound(episode, values).ifPresent(found::add);
            }
        }
        for (int i = 0; i < sorted.size(); i++) {
            EpisodeSummary episode = sorted.get(i);
            Instant next = i + 1 < sorted.size() ? sorted.get(i + 1).startAt() : null;
            if (episode.effectiveContext() == PhotoContext.MEAL || episode.effectiveContext() == PhotoContext.SNACK) {
                bigRiseWithoutInsulin(episode, next, values, insulinEvents).ifPresent(found::add);
                lateRiseAfterFat(episode, next, values).ifPresent(found::add);
            }
        }
        fastingNightRise(date, values, sorted, previousDayEpisodes).ifPresent(found::add);

        return found.stream().sorted(Comparator.comparingInt(ReportInsight::priority)).limit(MAX_INSIGHTS).toList();
    }

    // MARK: 흐름별 규칙

    /** 새벽(0~8시)에 먹은 기록 없이 40 이상 오른 흐름 */
    private Optional<ReportInsight> fastingNightRise(LocalDate date, List<GlucoseSample> values,
            List<EpisodeSummary> episodes, List<EpisodeSummary> previous) {
        Instant midnight = date.atStartOfDay(KST).toInstant();
        Instant morning = midnight.plus(Duration.ofHours(8));
        boolean ateAtNight = episodes.stream().anyMatch(e -> e.startAt().isBefore(morning))
                || previous.stream().anyMatch(e -> !e.startAt().isBefore(midnight.minus(Duration.ofHours(3))));
        if (ateAtNight) return Optional.empty();
        Optional<GlucoseSample> low = min(values, midnight, midnight.plus(Duration.ofHours(5)));
        if (low.isEmpty()) return Optional.empty();
        Optional<GlucoseSample> high = max(values, low.get().time().plusSeconds(1), morning);
        if (high.isEmpty() || high.get().value() - low.get().value() < 40) return Optional.empty();
        return Optional.of(new ReportInsight("NIGHT_FASTING_RISE", 50,
                "먹지 않은 새벽에 혈당이 올랐어요",
                DailyStoryBuilder.time(low.get().time()) + "쯤 " + low.get().value() + "이던 혈당이 "
                        + DailyStoryBuilder.time(high.get().time()) + "쯤 " + high.get().value()
                        + "까지 올랐고, 그 사이 음식 기록은 없어요. 이런 흐름은 새벽에 나오는 호르몬이 혈당을 올리는 '새벽 현상'일 가능성이 있어요. "
                        + "전날 밤 인슐린 효과가 줄었거나, 기록하지 않은 야식이 있어도 비슷하게 보일 수 있어요. 며칠 반복되면 기록을 가지고 의료진과 확인해 보세요.",
                List.of(ADA_MORNING, MAYO_DAWN)));
    }

    /** 식사·간식 뒤 60 이상(또는 200 이상) 올랐는데 앞뒤 1시간 안에 인슐린 기록이 없다 */
    private Optional<ReportInsight> bigRiseWithoutInsulin(EpisodeSummary episode, Instant next, List<GlucoseSample> values,
            List<DailyReportResponse.InsulinEventMarker> insulinEvents) {
        Instant start = episode.startAt();
        boolean insulinNearby = insulinEvents.stream().anyMatch(event ->
                Math.abs(Duration.between(start, event.occurredAt()).toMinutes()) <= 60);
        if (insulinNearby) return Optional.empty();
        Optional<GlucoseSample> base = last(values, start.minus(Duration.ofMinutes(30)), start);
        Optional<GlucoseSample> peak = max(values, start.plusSeconds(1), cut(start.plus(Duration.ofHours(3)), next));
        if (base.isEmpty() || peak.isEmpty()) return Optional.empty();
        int rise = peak.get().value() - base.get().value();
        if (rise < 60 && peak.get().value() < 200) return Optional.empty();
        String foods = foods(episode);
        Set<String> tags = episode.tagSet();
        String fast = tags.contains("FAST_SUGAR") || tags.contains("HIGH_CARB")
                ? foods + "처럼 탄수화물이 많거나 당이 빨리 흡수되는 음식은 혈당을 빠르게 올리는 것으로 알려져 있어요. "
                : "";
        return Optional.of(new ReportInsight("BIG_RISE_NO_INSULIN", 30,
                "인슐린 기록이 없는 식사 뒤 크게 올랐어요",
                DailyStoryBuilder.time(start) + " " + foods + " 뒤 " + base.get().value() + "에서 " + peak.get().value()
                        + "까지 올랐고, 앞뒤 1시간 안에 인슐린 기록이 없어요. " + fast
                        + "인슐린을 맞았는데 기록을 빠뜨렸다면 기록을 더해 주세요. 식사 때 인슐린은 의료진과 정한 방법을 따라 주세요.",
                List.of(ADA_HYPER)));
    }

    /** 지방이 많은 음식 뒤 2시간 30분 넘게 지나 가장 높았다 */
    private Optional<ReportInsight> lateRiseAfterFat(EpisodeSummary episode, Instant next, List<GlucoseSample> values) {
        if (!episode.tagSet().contains("HIGH_FAT")) return Optional.empty();
        Instant start = episode.startAt();
        Optional<GlucoseSample> base = last(values, start.minus(Duration.ofMinutes(30)), start);
        Optional<GlucoseSample> peak = max(values, start.plusSeconds(1), cut(start.plus(Duration.ofHours(5)), next));
        if (base.isEmpty() || peak.isEmpty()) return Optional.empty();
        Duration until = Duration.between(start, peak.get().time());
        if (until.compareTo(Duration.ofMinutes(150)) < 0 || peak.get().value() - base.get().value() < 40) return Optional.empty();
        return Optional.of(new ReportInsight("LATE_RISE_HIGH_FAT", 60,
                "기름진 음식 뒤 늦게 오른 흐름이에요",
                DailyStoryBuilder.time(start) + " " + foods(episode) + " 뒤 " + DailyStoryBuilder.duration(until)
                        + " 지나서 가장 높았어요(" + peak.get().value() + "). 지방이 많은 음식은 소화가 느려 몇 시간 뒤에 혈당이 오르는 경우가 연구로 알려져 있어요. "
                        + "이런 식사 뒤에는 몇 시간 뒤 흐름도 함께 살펴보세요.",
                List.of(BELL_2015)));
    }

    /** 오늘 또는 전날 밤 술 기록 뒤 12시간 안에 70 미만 */
    private Optional<ReportInsight> alcoholLateLow(List<GlucoseSample> values, List<EpisodeSummary> episodes,
            List<EpisodeSummary> previous) {
        List<EpisodeSummary> drinks = new ArrayList<>();
        previous.stream().filter(e -> e.effectiveContext() == PhotoContext.ALCOHOL).forEach(drinks::add);
        episodes.stream().filter(e -> e.effectiveContext() == PhotoContext.ALCOHOL).forEach(drinks::add);
        for (EpisodeSummary drink : drinks) {
            Instant from = drink.startAt().plus(Duration.ofHours(2));
            Instant to = drink.startAt().plus(Duration.ofHours(properties.alcoholWindowHours()));
            Optional<GlucoseSample> low = min(values, from, to).filter(s -> s.value() < properties.hypoGlucoseThreshold());
            if (low.isPresent()) {
                String when = previous.contains(drink) ? "전날 " + DailyStoryBuilder.time(drink.startAt()) : DailyStoryBuilder.time(drink.startAt());
                return Optional.of(new ReportInsight("ALCOHOL_LATE_LOW", 10,
                        "술을 마시고 몇 시간 뒤 낮은 값이 읽혔어요",
                        when + "에 " + foods(drink) + " 기록이 있고, " + DailyStoryBuilder.time(low.get().time()) + "쯤 "
                                + low.get().value() + "까지 낮게 읽혔어요. 술은 간이 포도당을 내보내는 일을 늦춰, 마신 뒤 몇 시간이 지나 혈당이 낮아질 수 있다고 알려져 있어요. "
                                + "술을 마신 날에는 자기 전과 다음 날 아침 혈당을 확인하라는 안내가 있어요.",
                        List.of(ADA_ALCOHOL)));
            }
        }
        return Optional.empty();
    }

    /** 지방이 많은 음식으로 저혈당에 대응했고 70 이상으로 올라오기까지 30분 넘게 걸렸다 */
    private Optional<ReportInsight> slowTreatment(EpisodeSummary episode, List<GlucoseSample> values) {
        if (!episode.tagSet().contains("HIGH_FAT")) return Optional.empty();
        Instant start = episode.startAt();
        Optional<GlucoseSample> recovered = between(values, start.plusSeconds(1), start.plus(Duration.ofHours(2))).stream()
                .filter(s -> s.value() >= properties.hypoGlucoseThreshold()).findFirst();
        Duration took = recovered.map(s -> Duration.between(start, s.time())).orElse(Duration.ofHours(2));
        if (took.compareTo(Duration.ofMinutes(30)) <= 0) return Optional.empty();
        return Optional.of(new ReportInsight("SLOW_TREATMENT_HIGH_FAT", 20,
                "저혈당 때 먹은 음식은 천천히 흡수될 수 있어요",
                DailyStoryBuilder.time(start) + "에 " + foods(episode) + DailyStoryBuilder.object(foods(episode)) + " 먹었고, 70 이상으로 올라오기까지 "
                        + (recovered.isPresent() ? DailyStoryBuilder.duration(took) + " 걸렸어요. " : "2시간 넘게 걸렸어요. ")
                        + "초콜릿처럼 지방이 많은 음식은 당 흡수가 느려, 저혈당 대응에는 포도당·주스처럼 빨리 흡수되는 당을 15g 정도 먹고 15분 뒤 다시 확인하는 방법이 권장돼요. "
                        + "의료진과 정한 방법이 있으면 그 방법을 따라 주세요.",
                List.of(ADA_HYPO)));
    }

    /** 저혈당 대응 뒤 2시간 안에 반동 기준을 넘었다 */
    private Optional<ReportInsight> treatmentRebound(EpisodeSummary episode, List<GlucoseSample> values) {
        Instant start = episode.startAt();
        Optional<GlucoseSample> top = max(values, start.plusSeconds(1),
                start.plus(Duration.ofHours(properties.hypoTreatmentWindowHours())));
        if (top.isEmpty() || top.get().value() <= properties.reboundGlucoseThreshold()) return Optional.empty();
        return Optional.of(new ReportInsight("TREATMENT_REBOUND", 25,
                "저혈당 대응 뒤 높아졌어요",
                DailyStoryBuilder.time(start) + "에 " + foods(episode) + DailyStoryBuilder.object(foods(episode)) + " 먹은 뒤 " + properties.hypoTreatmentWindowHours()
                        + "시간 안에 " + top.get().value() + "까지 읽혔어요. 낮을 때 한 번에 많이 먹으면 나중에 높아질 수 있어, "
                        + "빠른 당을 조금 먹고 15분 뒤 다시 확인하는 '15-15 원칙'이 권장돼요. 의료진과 정한 방법이 있으면 그 방법을 따라 주세요.",
                List.of(ADA_HYPO)));
    }

    // MARK: 도움 함수

    private static String foods(EpisodeSummary episode) {
        return episode.foods().isEmpty() ? ReportSummaryBuilder.label(episode.effectiveContext()) : String.join(", ", episode.foods());
    }

    private static Instant cut(Instant end, Instant next) {
        return next != null && next.isBefore(end) ? next : end;
    }

    private static List<GlucoseSample> between(List<GlucoseSample> values, Instant from, Instant to) {
        return values.stream().filter(s -> !s.time().isBefore(from) && !s.time().isAfter(to)).toList();
    }

    private static Optional<GlucoseSample> max(List<GlucoseSample> values, Instant from, Instant to) {
        return between(values, from, to).stream().max(Comparator.comparing(GlucoseSample::value));
    }

    private static Optional<GlucoseSample> min(List<GlucoseSample> values, Instant from, Instant to) {
        return between(values, from, to).stream().min(Comparator.comparing(GlucoseSample::value));
    }

    private static Optional<GlucoseSample> last(List<GlucoseSample> values, Instant from, Instant to) {
        List<GlucoseSample> found = between(values, from, to);
        return found.isEmpty() ? Optional.empty() : Optional.of(found.get(found.size() - 1));
    }
}
