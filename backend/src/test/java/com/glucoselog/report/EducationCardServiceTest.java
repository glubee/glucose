package com.glucoselog.report;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.test.util.ReflectionTestUtils;

import com.glucoselog.episode.GlucoseSample;
import com.glucoselog.glucose.ReadingFlag;
import com.glucoselog.intake.Intake;
import com.glucoselog.intake.IntakeRepository;
import com.glucoselog.photo.PhotoContext;

class EducationCardServiceTest {
    private static final UUID USER = UUID.randomUUID();
    private static final LocalDate DATE = LocalDate.of(2026, 10, 28);
    private final EducationCardRepository repository = mock(EducationCardRepository.class);
    private final IntakeRepository intakes = mock(IntakeRepository.class);
    private final EducationCardService service = new EducationCardService(repository, intakes,
            new ReportProperties(new BigDecimal("0.7")));

    @BeforeEach
    void setup() {
        when(repository.findByPlacementAndApprovedTrueOrderBySortOrderAscCodeAsc(EducationCardPlacement.DAILY))
                .thenReturn(Arrays.stream(EducationCardTrigger.values()).map(EducationCardServiceTest::card).toList());
        when(intakes.findByUserIdAndOccurredAtGreaterThanEqualAndOccurredAtLessThan(any(), any(), any()))
                .thenReturn(List.of());
    }

    @Test
    void 모든_조건을_독립적으로_선택하고_같은_조건의_여러_관측은_중복하지_않는다() {
        when(intakes.findByUserIdAndOccurredAtGreaterThanEqualAndOccurredAtLessThan(any(), any(), any()))
                .thenReturn(List.of(intake(PhotoContext.HYPO_TREATMENT), intake(PhotoContext.ALCOHOL)));
        var episodes = List.of(new EpisodeSummary(Instant.parse("2026-10-27T15:00:00Z"), PhotoContext.SNACK,
                PhotoContext.HYPO_TREATMENT, true, Instant.parse("2026-10-27T17:00:00Z"), true, 3));
        var result = service.dailyCards(USER, DATE, day("0.69", List.of(
                sample("00:00", 65, ReadingFlag.NORMAL), sample("05:45", 60, ReadingFlag.BELOW_RANGE),
                sample("14:00", 350, ReadingFlag.ABOVE_RANGE))), episodes);
        assertThat(result).extracting(EducationCardResponse::trigger)
                .containsExactly(EducationCardTrigger.values());
        assertThat(result).allSatisfy(card -> {
            assertThat(card.reviewedBy()).isEqualTo("요청자");
            assertThat(card.reviewedAt()).isEqualTo(DATE);
            assertThat(card.reviewType()).isEqualTo("REQUESTER");
            assertThat(card.sources()).isNotEmpty();
        });
        verify(intakes).findByUserIdAndOccurredAtGreaterThanEqualAndOccurredAtLessThan(USER,
                Instant.parse("2026-10-27T15:00:00Z"), Instant.parse("2026-10-28T15:00:00Z"));
    }

    @ParameterizedTest
    @CsvSource({"00:00,69,true", "05:59,69,true", "06:00,69,false", "23:59,69,false", "00:00,70,false"})
    void 밤_조건은_한국시간_0시_포함_6시_미포함이고_70_미만이다(String time, int value, boolean night) {
        var result = service.dailyCards(USER, DATE, day("1", List.of(sample(time, value, ReadingFlag.NORMAL))), List.of());
        assertThat(result.stream().anyMatch(card -> card.trigger() == EducationCardTrigger.NIGHT_LOW)).isEqualTo(night);
        assertThat(result.stream().anyMatch(card -> card.trigger() == EducationCardTrigger.LOW_READING)).isEqualTo(value < 70);
    }

    @ParameterizedTest
    @CsvSource({"0.69,true", "0.70,false", "1.0,false"})
    void 일부만_읽힌_카드는_기록_충분성_기준_미만에서만_붙는다(String coverage, boolean expected) {
        var result = service.dailyCards(USER, DATE, day(coverage, List.of(sample("12:00", 120, ReadingFlag.NORMAL))), List.of());
        assertThat(result.stream().anyMatch(card -> card.trigger() == EducationCardTrigger.LOW_COVERAGE)).isEqualTo(expected);
    }

    @Test
    void 그래프가_없거나_값이_누락됐으면_낮은_수치를_추측하지_않는다() {
        assertThat(service.dailyCards(USER, DATE, Optional.empty(), List.of())).isEmpty();
        assertThat(service.dailyCards(USER, DATE, day("1", List.of(
                sample("01:00", null, ReadingFlag.MISSING), sample("02:00", 40, ReadingFlag.MISSING))), List.of())).isEmpty();
    }

    @Test
    void 자동_재분류는_사용자가_대응_음식을_기록한_것으로_간주하지_않는다() {
        var episode = new EpisodeSummary(Instant.parse("2026-10-27T16:00:00Z"), PhotoContext.SNACK,
                PhotoContext.HYPO_TREATMENT, true, Instant.parse("2026-10-27T18:00:00Z"), null, 1);
        when(intakes.findByUserIdAndOccurredAtGreaterThanEqualAndOccurredAtLessThan(any(), any(), any()))
                .thenReturn(List.of(intake(PhotoContext.SNACK)));
        assertThat(service.dailyCards(USER, DATE, Optional.empty(), List.of(episode))).isEmpty();
    }

    @Test
    void 그래프가_없어도_직접_남긴_처치와_술_기록은_안내할_수_있다() {
        when(intakes.findByUserIdAndOccurredAtGreaterThanEqualAndOccurredAtLessThan(any(), any(), any()))
                .thenReturn(List.of(intake(PhotoContext.ALCOHOL), intake(PhotoContext.HYPO_TREATMENT)));
        assertThat(service.dailyCards(USER, DATE, Optional.empty(), List.of()))
                .extracting(EducationCardResponse::trigger)
                .containsExactly(EducationCardTrigger.HYPO_TREATED, EducationCardTrigger.ALCOHOL);
    }

    @Test
    void 날짜_밖_샘플은_그날_조건에_포함하지_않는다() {
        var outside = new GlucoseSample(Instant.parse("2026-10-28T15:00:00Z"), 50, ReadingFlag.BELOW_RANGE);
        assertThat(service.dailyCards(USER, DATE, day("1", List.of(outside)), List.of())).isEmpty();
    }

    private static GlucoseSample sample(String time, Integer value, ReadingFlag flag) {
        return new GlucoseSample(DATE.atTime(java.time.LocalTime.parse(time)).atZone(java.time.ZoneId.of("Asia/Seoul"))
                .toInstant(), value, flag);
    }

    private static Optional<GlucoseTimelineService.DaySummary> day(String coverage, List<GlucoseSample> samples) {
        return Optional.of(new GlucoseTimelineService.DaySummary(new BigDecimal(coverage), samples));
    }

    private static Intake intake(PhotoContext context) {
        return new Intake(USER, null, context, Instant.parse("2026-10-28T00:00:00Z"));
    }

    private static EducationCard card(EducationCardTrigger trigger) {
        var card = new EducationCard();
        ReflectionTestUtils.setField(card, "code", trigger.name());
        ReflectionTestUtils.setField(card, "trigger", trigger);
        ReflectionTestUtils.setField(card, "sources", List.of(new EducationCardSource("공식 출처", "https://diabetes.org/", "EXTERNAL")));
        ReflectionTestUtils.setField(card, "reviewedBy", "요청자");
        ReflectionTestUtils.setField(card, "reviewedAt", DATE);
        ReflectionTestUtils.setField(card, "reviewType", "REQUESTER");
        return card;
    }
}
