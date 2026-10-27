package com.glucoselog.report;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.glucoselog.episode.EpisodeProperties;
import com.glucoselog.insulin.InsulinEvent;
import com.glucoselog.insulin.InsulinEventRepository;
import com.glucoselog.intake.IntakeRepository;

@Service
@Transactional(readOnly=true)
public class FoodObservationService {
    private final IntakeRepository intakes;
    private final InsulinEventRepository insulin;
    private final GlucoseTimelineService timeline;
    private final FoodObservationAnalyzer analyzer;
    private final EpisodeProperties windows;
    private final FoodObservationProperties properties;
    private final Clock clock;

    public FoodObservationService(IntakeRepository intakes, InsulinEventRepository insulin,
            GlucoseTimelineService timeline, FoodObservationAnalyzer analyzer, EpisodeProperties windows,
            FoodObservationProperties properties, Clock clock) {
        this.intakes=intakes; this.insulin=insulin; this.timeline=timeline; this.analyzer=analyzer;
        this.windows=windows; this.properties=properties; this.clock=clock;
    }

    public FoodObservationResponse daily(UUID userId, LocalDate date) {
        return report("DAILY",userId,date,date);
    }

    public FoodObservationResponse weekly(UUID userId, LocalDate date) {
        LocalDate start=date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        return report("WEEKLY",userId,start,start.plusDays(6));
    }

    private FoodObservationResponse report(String kind, UUID userId, LocalDate from, LocalDate to) {
        int maxHours=Math.max(windows.mealWindowHours(),Math.max(windows.hypoTreatmentWindowHours(),windows.alcoholWindowHours()));
        var queryFrom=from.atStartOfDay(FoodObservationAnalyzer.KST).toInstant()
                .minus(Duration.ofHours(maxHours)).minus(Duration.ofMinutes(properties.baselineMaxAgeMinutes()));
        var queryTo=to.plusDays(1).atStartOfDay(FoodObservationAnalyzer.KST).toInstant().plus(Duration.ofHours(maxHours));
        var records=intakes.findForFoodReport(userId,queryFrom,queryTo).stream()
                .map(intake -> new FoodObservationAnalyzer.IntakeRecord(intake.getId(),intake.getOccurredAt(),intake.getContext(),
                        intake.getItems().stream().filter(item -> item.getName()!=null && !item.getName().isBlank())
                                .map(item -> new FoodObservationResponse.Food(item.getName(),item.getCount(),item.getUnit())).toList()))
                .toList();
        int paddingDays=Math.max(1,(maxHours+23)/24);
        var samples=timeline.loadRange(userId,from.minusDays(paddingDays),to.plusDays(paddingDays));
        var injections=insulin.findByUserIdAndOccurredAtGreaterThanEqualAndOccurredAtLessThan(userId,queryFrom,queryTo)
                .stream().map(InsulinEvent::getOccurredAt).toList();
        return analyzer.analyze(kind,from,to,records,samples,injections,clock.instant());
    }
}
