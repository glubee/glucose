package com.glucoselog.report;

import static com.glucoselog.report.FoodObservationResponse.*;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.text.Normalizer;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.*;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;
import com.glucoselog.episode.EpisodeProperties;
import com.glucoselog.episode.GlucoseSample;
import com.glucoselog.glucose.ReadingFlag;
import com.glucoselog.photo.PhotoContext;

/** Pure observation calculations; never infers an individual food's causal effect. */
@Component
public class FoodObservationAnalyzer {
    static final int INTERVAL = 15;
    static final ZoneId KST = ZoneId.of("Asia/Seoul");
    static final List<String> LIMITATIONS = List.of(
            "음식명·분량·시각은 등록된 기록 기준이며 실제 섭취 내용·시각과 다를 수 있어요.",
            "혈당은 그래프에서 읽은 15분 간격 추정값이에요. 공백을 채우지 않았고 읽힌 최고가 실제 최고와 같지는 않아요.",
            "인슐린·활동·다른 섭취·제품과 분량 차이를 통제한 비교가 아니므로 음식 하나의 영향으로 해석할 수 없어요.");
    public record IntakeRecord(UUID id, Instant time, PhotoContext context, List<Food> foods) {}
    private record FoodKey(String name, Integer count, String unit) {}
    private record RepeatKey(PhotoContext context, List<FoodKey> foods) {}
    private final EpisodeProperties windows;
    private final ReportProperties report;
    private final FoodObservationProperties properties;

    public FoodObservationAnalyzer(EpisodeProperties windows, ReportProperties report, FoodObservationProperties properties) {
        if (windows.mealWindowHours()<1 || windows.hypoTreatmentWindowHours()<1 || windows.alcoholWindowHours()<1) {
            throw new IllegalArgumentException("Observation windows must be positive");
        }
        this.windows=windows; this.report=report; this.properties=properties;
    }

    public FoodObservationResponse analyze(String kind, LocalDate from, LocalDate to,
            List<IntakeRecord> intakes, List<GlucoseSample> samples, List<Instant> insulin, Instant now) {
        TreeMap<Instant,GlucoseSample> timeline = new TreeMap<>();
        Set<Instant> duplicates = new HashSet<>();
        for (var sample : samples) {
            if (sample.time().isAfter(now) || sample.time().getNano()!=0 || sample.time().getEpochSecond() % (INTERVAL*60) != 0) continue;
            if (timeline.putIfAbsent(sample.time(),sample) != null) duplicates.add(sample.time());
        }
        duplicates.forEach(time -> timeline.put(time,new GlucoseSample(time,null,ReadingFlag.MISSING)));
        Instant start=from.atStartOfDay(KST).toInstant(), end=to.plusDays(1).atStartOfDay(KST).toInstant();
        var observations = intakes.stream()
                .filter(intake -> !intake.time().isBefore(start) && intake.time().isBefore(end))
                .sorted(Comparator.comparing(IntakeRecord::time).thenComparing(IntakeRecord::id))
                .map(intake -> observe(intake,intakes,timeline,duplicates,insulin,now)).toList();
        return new FoodObservationResponse(kind,from,to,INTERVAL,observations,
                "WEEKLY".equals(kind) ? repeat(observations) : List.of(),LIMITATIONS);
    }

    private Observation observe(IntakeRecord intake, List<IntakeRecord> all, TreeMap<Instant,GlucoseSample> timeline,
            Set<Instant> duplicates, List<Instant> insulin, Instant now) {
        Instant start=intake.time(), end=start.plus(window(intake.context()));
        boolean ongoing=end.isAfter(now);
        var reasons = new LinkedHashSet<String>();
        if (ongoing) reasons.add(start.isAfter(now) ? "WINDOW_NOT_STARTED" : "WINDOW_INCOMPLETE");
        var preceding=timeline.floorEntry(start);
        Reading baseline=null;
        if (preceding == null || preceding.getValue().value() == null) reasons.add("MISSING_BASELINE");
        else if (Duration.between(preceding.getKey(),start).compareTo(Duration.ofMinutes(properties.baselineMaxAgeMinutes()))>0) reasons.add("STALE_BASELINE");
        else if (!normal(preceding.getValue())) reasons.add("CLIPPED_BASELINE");
        else baseline=reading(preceding.getValue());
        var after=timeline.values().stream().filter(s -> s.time().isAfter(start) && !s.time().isAfter(end)).toList();
        var usable=after.stream().filter(FoodObservationAnalyzer::normal).toList();
        int expected=(int)window(intake.context()).toMinutes()/INTERVAL;
        BigDecimal coverage=BigDecimal.valueOf(usable.size()).divide(BigDecimal.valueOf(expected),4,RoundingMode.HALF_UP);
        int clipped=(int)after.stream().filter(s -> s.flag()==ReadingFlag.ABOVE_RANGE || s.flag()==ReadingFlag.BELOW_RANGE).count();
        if (usable.size() < expected) reasons.add("MISSING_SEGMENT");
        if (usable.size() < 2 || coverage.compareTo(report.sufficientCoverageRatio())<0) reasons.add("LOW_COVERAGE");
        if (clipped>0) reasons.add("CLIPPED_VALUE");
        if (duplicates.stream().anyMatch(time -> !time.isBefore(start.minus(Duration.ofMinutes(properties.baselineMaxAgeMinutes()))) && !time.isAfter(end))) reasons.add("DUPLICATE_SAMPLE");
        Reading peak=clipped>0?null:usable.stream().max(Comparator.comparing(GlucoseSample::value)
                .thenComparing(GlucoseSample::time,Comparator.reverseOrder())).map(FoodObservationAnalyzer::reading).orElse(null);
        Reading last=null;
        var ending=timeline.floorEntry(end);
        if (!ongoing && ending!=null && ending.getKey().isAfter(start) && normal(ending.getValue())
                && Duration.between(ending.getKey(),end).compareTo(Duration.ofMinutes(INTERVAL))<=0) last=reading(ending.getValue());
        if (!ongoing && last==null) reasons.add("MISSING_END");
        Instant observedUntil=end.isBefore(now)?end:now;
        var overlapping=all.stream().filter(other -> !other.id().equals(intake.id()))
                .filter(other -> !other.time().isAfter(observedUntil) && other.time().isBefore(end)
                        && other.time().plus(window(other.context())).isAfter(start))
                .map(IntakeRecord::id).distinct().toList();
        if (!overlapping.isEmpty()) reasons.add("OVERLAPPING_INTAKES");
        Instant insulinFrom=baseline==null?start.minus(Duration.ofMinutes(properties.baselineMaxAgeMinutes())):baseline.time();
        int insulinCount=(int)insulin.stream().filter(time -> !time.isBefore(insulinFrom) && !time.isAfter(observedUntil)).count();
        if (insulinCount>0) reasons.add("INSULIN_RECORDED");
        if (intake.foods().isEmpty()) reasons.add("NO_FOOD_NAME");
        Integer peakDelta=baseline==null || peak==null ? null : peak.value()-baseline.value();
        Integer endDelta=baseline==null || last==null ? null : last.value()-baseline.value();
        boolean comparable=!ongoing && baseline!=null && last!=null && usable.size()>=2
                && coverage.compareTo(report.sufficientCoverageRatio())>=0 && clipped==0 && overlapping.isEmpty()
                && !reasons.contains("DUPLICATE_SAMPLE") && !intake.foods().isEmpty();
        String status=ongoing?"IN_PROGRESS":baseline==null || usable.isEmpty()?"UNAVAILABLE":reasons.isEmpty()?"OBSERVED":"LIMITED";
        var notes=new ArrayList<String>();
        if (ongoing) notes.add("관찰 구간이 아직 끝나지 않아 주간 비교에서는 제외했어요.");
        if (baseline==null) notes.add("기록 직전의 최근 값을 확인할 수 없어 전후 차이는 계산하지 않았어요.");
        if (usable.size()<expected) notes.add("구간의 일부 값이 없어요. 읽힌 값만 사용했어요.");
        if (clipped>0) notes.add("관찰 구간에 그래프 경계에 붙은 값이 있어 최고값과 그 차이는 확정하지 않았어요.");
        if (reasons.contains("CLIPPED_BASELINE")) notes.add("기록 직전 값이 그래프 경계에 붙어 있어 정확한 전후 비교에서 제외했어요.");
        if (!overlapping.isEmpty()) notes.add("관찰 구간이 겹치는 다른 섭취 기록 "+overlapping.size()+"건이 있어 주간 수치 비교에서 제외했어요.");
        if (insulinCount>0) notes.add("직전 값부터 관찰 구간 사이에 인슐린 기록 "+insulinCount+"건이 함께 있어요. 음식만의 영향으로 구분할 수 없어요.");
        if (reasons.contains("DUPLICATE_SAMPLE")) notes.add("같은 시각의 중복 값이 있어 해당 값과 주간 비교를 제외했어요.");
        String summary=title(intake.foods())+" 기록 뒤 "+window(intake.context()).toHours()+"시간 구간"+(ongoing?"을 관찰 중이에요.":"에서 읽힌 값을 정리했어요.");
        if (peakDelta!=null) summary+=" 기록 전 "+baseline.value()+", 이후 읽힌 최고 "+peak.value()+" mg/dL로 차이는 "+signed(peakDelta)+" mg/dL예요.";
        else summary+=" 전후 차이를 계산할 자료가 부족해요.";
        return new Observation(intake.id(),start,intake.context(),intake.foods(),end,(int)window(intake.context()).toMinutes(),
                status,baseline,peak,peakDelta,last,endDelta,usable.size(),expected,coverage,clipped,
                overlapping,insulinCount,comparable,List.copyOf(reasons),List.copyOf(notes),summary);
    }

    private List<RepeatedFood> repeat(List<Observation> observations) {
        Map<RepeatKey,List<Observation>> groups=new LinkedHashMap<>();
        for (var observation:observations) {
            if (observation.foods().isEmpty() || !(observation.context()==PhotoContext.MEAL || observation.context()==PhotoContext.SNACK)) continue;
            var foods=observation.foods().stream().map(food -> new FoodKey(normalize(food.name()),food.count(),normalize(food.unit())))
                    .sorted(Comparator.comparing(FoodKey::name).thenComparing(key -> Objects.toString(key.count(),"?"))
                            .thenComparing(FoodKey::unit)).toList();
            groups.computeIfAbsent(new RepeatKey(observation.context(),foods),key -> new ArrayList<>()).add(observation);
        }
        List<RepeatedFood> result=new ArrayList<>();
        for (var entry:groups.entrySet()) {
            var group=entry.getValue();
            if (group.size()<2) continue;
            var usable=group.stream().filter(Observation::comparable).toList();
            int days=(int)usable.stream().map(item -> item.occurredAt().atZone(KST).toLocalDate()).distinct().count();
            boolean enough=usable.size()>=properties.minimumRepeatRecords() && days>=properties.minimumRepeatDays();
            BigDecimal mean=enough?BigDecimal.valueOf(usable.stream().mapToLong(Observation::peakDelta).sum())
                    .divide(BigDecimal.valueOf(usable.size()),1,RoundingMode.HALF_UP):null;
            Integer min=enough?usable.stream().mapToInt(Observation::peakDelta).min().orElseThrow():null;
            Integer max=enough?usable.stream().mapToInt(Observation::peakDelta).max().orElseThrow():null;
            var foods=group.getFirst().foods();
            boolean unknown=foods.stream().anyMatch(food -> food.count()==null || food.unit()==null || food.unit().isBlank());
            int insulinCount=(int)usable.stream().filter(item -> item.insulinEventsCount()>0).count();
            String summary=title(foods)+" 조합의 기록이 "+group.size()+"건 있고, 비교 조건을 충족한 관찰은 "+usable.size()+"건이에요.";
            if (enough) summary+=" 읽힌 최고와 기록 전 값의 차이는 평균 "+signed(mean)+" mg/dL예요.";
            else summary+=" 서로 다른 "+properties.minimumRepeatDays()+"일의 관찰 "+properties.minimumRepeatRecords()+"건 이상이 확보되면 차이를 요약해요.";
            if (insulinCount>0) summary+=" 그중 인슐린 기록이 함께 있는 관찰은 "+insulinCount+"건이에요.";
            if (unknown) summary+=" 분량이 확인되지 않은 기록이 포함돼 있어요.";
            result.add(new RepeatedFood(UUID.nameUUIDFromBytes(entry.getKey().toString().getBytes(StandardCharsets.UTF_8)).toString(),
                    entry.getKey().context(),foods,group.size(),usable.size(),days,insulinCount,unknown,mean,min,max,
                    group.stream().map(Observation::intakeId).toList(),usable.stream().map(Observation::intakeId).toList(),summary));
        }
        return result.stream().sorted(Comparator.comparing(item -> title(item.foods()))).toList();
    }

    Duration window(PhotoContext context) {
        return Duration.ofHours(switch(context) {
            case MEAL,SNACK -> windows.mealWindowHours();
            case HYPO_TREATMENT -> windows.hypoTreatmentWindowHours();
            case ALCOHOL -> windows.alcoholWindowHours();
        });
    }
    private static boolean normal(GlucoseSample sample) { return sample.value()!=null && sample.flag()==ReadingFlag.NORMAL; }
    private static Reading reading(GlucoseSample sample) { return new Reading(sample.time(),sample.value()); }
    private static String normalize(String value) { return value==null?"":Normalizer.normalize(value.trim(),Normalizer.Form.NFC).replaceAll("\\s+"," ").toLowerCase(Locale.ROOT); }
    private static String title(List<Food> foods) { return foods.isEmpty()?"음식명 없는 섭취":foods.stream().map(Food::name).collect(Collectors.joining(" · ")); }
    private static String signed(Number value) { return new BigDecimal(value.toString()).signum()>0?"+"+value:value.toString(); }
}
