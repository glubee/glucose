package com.glucoselog.report;

import static org.assertj.core.api.Assertions.assertThat;
import static com.glucoselog.report.FoodObservationResponse.*;

import java.math.BigDecimal;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import com.glucoselog.episode.EpisodeProperties;
import com.glucoselog.episode.GlucoseSample;
import com.glucoselog.glucose.ReadingFlag;
import com.glucoselog.photo.PhotoContext;

class FoodObservationAnalyzerTest {
    static final LocalDate MONDAY=LocalDate.of(2026,10,19);
    static final Instant NOW=Instant.parse("2026-10-27T03:00:00Z");
    final FoodObservationAnalyzer analyzer=new FoodObservationAnalyzer(new EpisodeProperties(90,4,2,12,70),
            new ReportProperties(new BigDecimal("0.7")),new FoodObservationProperties(15,2,2));

    static Instant at(LocalDate date,String time) { return date.atTime(LocalTime.parse(time)).atZone(FoodObservationAnalyzer.KST).toInstant(); }
    static FoodObservationAnalyzer.IntakeRecord meal(LocalDate date,String time,Food... foods) {
        return new FoodObservationAnalyzer.IntakeRecord(UUID.randomUUID(),at(date,time),PhotoContext.MEAL,List.of(foods));
    }
    static Food food(String name) { return new Food(name,1,"개"); }
    static List<GlucoseSample> samples(Instant start,int peak) {
        List<GlucoseSample> values=new ArrayList<>();
        for(int i=0;i<=16;i++) values.add(new GlucoseSample(start.plusSeconds(i*900L),i==4?peak:100+i*2,ReadingFlag.NORMAL));
        return values;
    }
    Observation observe(FoodObservationAnalyzer.IntakeRecord record,List<GlucoseSample> values) {
        LocalDate day=record.time().atZone(FoodObservationAnalyzer.KST).toLocalDate();
        return analyzer.analyze("DAILY",day,day,List.of(record),values,List.of(),NOW).observations().getFirst();
    }

    @Test void complete_window_computes_observed_peak_end_and_signed_changes() {
        var meal=meal(MONDAY,"09:00",food("김밥"));
        var result=observe(meal,samples(meal.time(),150));
        assertThat(result.baseline().value()).isEqualTo(100);
        assertThat(result.peak().value()).isEqualTo(150);
        assertThat(result.peak().time()).isEqualTo(meal.time().plusSeconds(3600));
        assertThat(result.peakDelta()).isEqualTo(50);
        assertThat(result.endReading().value()).isEqualTo(132);
        assertThat(result.endDelta()).isEqualTo(32);
        assertThat(result.readingsCount()).isEqualTo(16);
        assertThat(result.expectedReadingsCount()).isEqualTo(16);
        assertThat(result.coverageRatio()).isEqualByComparingTo("1");
        assertThat(result.comparable()).isTrue();
        assertThat(result.summary()).contains("김밥","읽힌 최고 150","+50 mg/dL").doesNotContain("때문에","정상","나쁜");
    }

    @Test void decreasing_values_are_not_forced_into_a_positive_rise() {
        var meal=meal(MONDAY,"09:00",food("샐러드"));
        var values=new ArrayList<GlucoseSample>();
        for(int i=0;i<=16;i++) values.add(new GlucoseSample(meal.time().plusSeconds(i*900L),150-i,ReadingFlag.NORMAL));
        var result=observe(meal,values);
        assertThat(result.peakDelta()).isEqualTo(-1);
        assertThat(result.endDelta()).isEqualTo(-16);
        assertThat(result.summary()).contains("-1 mg/dL");
    }

    @Test void latest_missing_baseline_is_not_replaced_by_an_older_normal_value() {
        var meal=meal(MONDAY,"09:00",food("김밥"));
        var values=samples(meal.time(),150);
        values.set(0,new GlucoseSample(meal.time(),null,ReadingFlag.MISSING));
        values.add(new GlucoseSample(meal.time().minusSeconds(900),100,ReadingFlag.NORMAL));
        var result=observe(meal,values);
        assertThat(result.baseline()).isNull();
        assertThat(result.peakDelta()).isNull();
        assertThat(result.reasonCodes()).contains("MISSING_BASELINE");
        assertThat(result.comparable()).isFalse();
    }

    @Test void a_baseline_older_than_exactly_fifteen_minutes_is_stale() {
        var meal=meal(MONDAY,"09:15:01",food("김밥"));
        var values=samples(at(MONDAY,"09:15"),150);
        values.set(0,new GlucoseSample(at(MONDAY,"09:00"),100,ReadingFlag.NORMAL));
        var result=observe(meal,values);
        assertThat(result.baseline()).isNull();
        assertThat(result.reasonCodes()).contains("STALE_BASELINE");
    }

    @Test void a_clipped_baseline_or_clipped_window_does_not_enter_repeat_statistics() {
        var meal=meal(MONDAY,"09:00",food("김밥"));
        var values=samples(meal.time(),150);
        values.set(0,new GlucoseSample(meal.time(),350,ReadingFlag.ABOVE_RANGE));
        assertThat(observe(meal,values).reasonCodes()).contains("CLIPPED_BASELINE");
        values=samples(meal.time(),150);
        values.set(4,new GlucoseSample(meal.time().plusSeconds(3600),350,ReadingFlag.ABOVE_RANGE));
        var result=observe(meal,values);
        assertThat(result.peak()).isNull();
        assertThat(result.peakDelta()).isNull();
        assertThat(result.clippedReadingsCount()).isEqualTo(1);
        assertThat(result.comparable()).isFalse();
    }

    @Test void ongoing_windows_ignore_future_values_and_do_not_enter_weekly_comparisons() {
        var meal=meal(MONDAY,"09:00",food("김밥"));
        var values=samples(meal.time(),150);
        values.add(new GlucoseSample(at(MONDAY,"12:30"),300,ReadingFlag.NORMAL));
        var result=analyzer.analyze("DAILY",MONDAY,MONDAY,List.of(meal),values,List.of(),at(MONDAY,"10:30")).observations().getFirst();
        assertThat(result.status()).isEqualTo("IN_PROGRESS");
        assertThat(result.peak().value()).isEqualTo(150);
        assertThat(result.endReading()).isNull();
        assertThat(result.comparable()).isFalse();
    }

    @Test void midnight_windows_keep_next_day_samples_but_belong_to_the_intake_day_only() {
        var meal=meal(MONDAY,"23:45",food("김밥"));
        var result=observe(meal,samples(meal.time(),150));
        assertThat(result.windowEndAt()).isEqualTo(at(MONDAY.plusDays(1),"03:45"));
        assertThat(result.readingsCount()).isEqualTo(16);
        assertThat(analyzer.analyze("DAILY",MONDAY.plusDays(1),MONDAY.plusDays(1),List.of(meal),
                samples(meal.time(),150),List.of(),NOW).observations()).isEmpty();
    }

    @Test void other_intakes_before_midnight_are_visible_as_overlapping_context() {
        var previous=meal(MONDAY,"23:45",food("김밥"));
        var current=meal(MONDAY.plusDays(1),"01:00",food("우유"));
        var result=analyzer.analyze("DAILY",MONDAY.plusDays(1),MONDAY.plusDays(1),List.of(previous,current),
                samples(current.time(),150),List.of(),NOW).observations().getFirst();
        assertThat(result.overlappingIntakeIds()).containsExactly(previous.id());
        assertThat(result.comparable()).isFalse();
    }

    @Test void insulin_records_are_disclosed_without_a_dose_or_effect_inference() {
        var meal=meal(MONDAY,"09:00",food("김밥"));
        var result=analyzer.analyze("DAILY",MONDAY,MONDAY,List.of(meal),samples(meal.time(),150),
                List.of(meal.time()),NOW).observations().getFirst();
        assertThat(result.insulinEventsCount()).isEqualTo(1);
        assertThat(result.notes().toString()).contains("인슐린 기록 1건","음식만의 영향으로 구분할 수 없어요");
        assertThat(result.comparable()).isTrue();
    }

    @Test void gaps_and_duplicate_timestamps_do_not_inflate_coverage_or_fill_values() {
        var meal=meal(MONDAY,"09:00",food("김밥"));
        var values=samples(meal.time(),150);
        values.removeIf(sample -> sample.time().equals(meal.time().plusSeconds(900)));
        values.add(new GlucoseSample(meal.time().plusSeconds(1800),300,ReadingFlag.NORMAL));
        var result=observe(meal,values);
        assertThat(result.readingsCount()).isEqualTo(14);
        assertThat(result.coverageRatio()).isEqualByComparingTo("0.875");
        assertThat(result.reasonCodes()).contains("MISSING_SEGMENT","DUPLICATE_SAMPLE");
        assertThat(result.peak().value()).isEqualTo(150);
        assertThat(result.comparable()).isFalse();
    }

    @Test void missing_or_empty_data_stays_unknown_not_zero() {
        var meal=meal(MONDAY,"09:00",food("김밥"));
        var result=observe(meal,List.of());
        assertThat(result.status()).isEqualTo("UNAVAILABLE");
        assertThat(result.baseline()).isNull();
        assertThat(result.peak()).isNull();
        assertThat(result.peakDelta()).isNull();
        assertThat(result.comparable()).isFalse();
        assertThat(result.summary()).contains("자료가 부족");
    }

    @Test void a_missing_final_slot_prevents_a_false_end_comparison() {
        var meal=meal(MONDAY,"09:00",food("김밥"));
        var values=samples(meal.time(),150);
        values.set(16,new GlucoseSample(meal.time().plusSeconds(14400),null,ReadingFlag.MISSING));
        var result=observe(meal,values);
        assertThat(result.endReading()).isNull();
        assertThat(result.endDelta()).isNull();
        assertThat(result.reasonCodes()).contains("MISSING_END");
        assertThat(result.comparable()).isFalse();
    }

    @ParameterizedTest
    @CsvSource({"11,false","12,true"})
    void minimum_observed_coverage_gates_weekly_comparison(int count,boolean comparable) {
        var meal=meal(MONDAY,"09:00",food("김밥"));
        var values=samples(meal.time(),150);
        for(int i=1;i<=16-count;i++) values.set(i,new GlucoseSample(meal.time().plusSeconds(i*900L),null,ReadingFlag.MISSING));
        var result=observe(meal,values);
        assertThat(result.readingsCount()).isEqualTo(count);
        assertThat(result.comparable()).isEqualTo(comparable);
        assertThat(result.reasonCodes()).contains("MISSING_SEGMENT");
    }

    @Test void weekly_repeats_use_only_eligible_windows_and_include_insulin_context() throws Exception {
        var first=meal(MONDAY,"09:00",food("김밥"));
        var second=meal(MONDAY.plusDays(1),"09:00",food("김밥"));
        var clipped=meal(MONDAY.plusDays(2),"09:00",food("김밥"));
        var values=new ArrayList<>(samples(first.time(),150));
        values.addAll(samples(second.time(),170));
        var third=samples(clipped.time(),350);
        third.set(4,new GlucoseSample(clipped.time().plusSeconds(3600),350,ReadingFlag.ABOVE_RANGE));
        values.addAll(third);
        var response=analyzer.analyze("WEEKLY",MONDAY,MONDAY.plusDays(6),List.of(first,second,clipped),values,List.of(first.time()),NOW);
        var result=response.repeatedFoods().getFirst();
        assertThat(result.recordsCount()).isEqualTo(3);
        assertThat(result.comparableCount()).isEqualTo(2);
        assertThat(result.comparisonDays()).isEqualTo(2);
        assertThat(result.meanPeakDelta()).isEqualByComparingTo("60");
        assertThat(result.minPeakDelta()).isEqualTo(50);
        assertThat(result.maxPeakDelta()).isEqualTo(70);
        assertThat(result.insulinAccompaniedCount()).isEqualTo(1);
        assertThat(result.comparableIntakeIds()).containsExactly(first.id(),second.id());
        assertThat(result.summary()).contains("+60.0 mg/dL").doesNotContain("때문에");
        String output=System.getenv("FOOD_OBSERVATION_SAMPLE_OUTPUT");
        if (output!=null) {
            var mapper=new com.fasterxml.jackson.databind.ObjectMapper().findAndRegisterModules()
                    .disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
                    .setPropertyNamingStrategy(com.fasterxml.jackson.databind.PropertyNamingStrategies.SNAKE_CASE);
            var daily=analyzer.analyze("DAILY",MONDAY,MONDAY,List.of(first,second,clipped),values,List.of(first.time()),NOW);
            java.nio.file.Files.writeString(java.nio.file.Path.of(output),mapper.writerWithDefaultPrettyPrinter()
                    .writeValueAsString(Map.of("synthetic_data_only",true,"daily",daily,"weekly",response)));
        }
    }

    @Test void repeat_comparison_requires_distinct_days_and_keeps_unknown_amounts_visible() {
        var first=meal(MONDAY,"09:00",new Food("김밥",null,null));
        var second=meal(MONDAY,"18:00",new Food("김밥",null,null));
        var values=new ArrayList<>(samples(first.time(),150));values.addAll(samples(second.time(),170));
        var result=analyzer.analyze("WEEKLY",MONDAY,MONDAY.plusDays(6),List.of(first,second),values,List.of(),NOW).repeatedFoods().getFirst();
        assertThat(result.meanPeakDelta()).isNull();
        assertThat(result.amountUnknown()).isTrue();
        assertThat(result.summary()).contains("분량이 확인되지 않은");
    }

    @Test void combinations_quantities_and_contexts_are_not_mixed_into_one_food_pattern() {
        var first=meal(MONDAY,"09:00",food("김밥"));
        var mixed=meal(MONDAY.plusDays(1),"09:00",food("김밥"),food("우유"));
        var doublePortion=meal(MONDAY.plusDays(2),"09:00",new Food("김밥",2,"개"));
        var treatment=new FoodObservationAnalyzer.IntakeRecord(UUID.randomUUID(),at(MONDAY.plusDays(3),"09:00"),PhotoContext.HYPO_TREATMENT,List.of(food("김밥")));
        assertThat(analyzer.analyze("WEEKLY",MONDAY,MONDAY.plusDays(6),List.of(first,mixed,doublePortion,treatment),
                List.of(),List.of(),NOW).repeatedFoods()).isEmpty();
    }
}
