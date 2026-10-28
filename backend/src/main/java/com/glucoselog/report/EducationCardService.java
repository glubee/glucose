package com.glucoselog.report;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.EnumSet;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.stereotype.Service;

import com.glucoselog.episode.GlucoseSample;
import com.glucoselog.glucose.ReadingFlag;
import com.glucoselog.intake.IntakeRepository;
import com.glucoselog.photo.PhotoContext;

@Service
public class EducationCardService {
    private static final ZoneId KST = ZoneId.of("Asia/Seoul");
    private final EducationCardRepository repository;
    private final IntakeRepository intakeRepository;
    private final ReportProperties properties;

    public EducationCardService(EducationCardRepository repository, IntakeRepository intakeRepository,
            ReportProperties properties) {
        this.repository = repository;
        this.intakeRepository = intakeRepository;
        this.properties = properties;
    }

    public List<EducationCardResponse> reviewCards() {
        return repository.findByPlacementAndApprovedTrueOrderBySortOrderAscCodeAsc(EducationCardPlacement.REVIEW)
                .stream().map(EducationCardResponse::from).toList();
    }

    public List<EducationCardResponse> dailyCards(UUID userId, LocalDate date,
            Optional<GlucoseTimelineService.DaySummary> summary, List<EpisodeSummary> episodes) {
        EnumSet<EducationCardTrigger> triggers = EnumSet.noneOf(EducationCardTrigger.class);
        // 그래프 미등록은 화면의 빈 상태로 안내한다. "일부만 읽혔다"는 카드는 표시하지 않는다.
        summary.ifPresent(day -> {
            if (day.coverageRatio() != null
                    && day.coverageRatio().compareTo(properties.sufficientCoverageRatio()) < 0) {
                triggers.add(EducationCardTrigger.LOW_COVERAGE);
            }
            for (GlucoseSample sample : day.samples()) {
                if (!sample.time().atZone(KST).toLocalDate().equals(date)) continue;
                if (sample.flag() == ReadingFlag.ABOVE_RANGE || sample.flag() == ReadingFlag.BELOW_RANGE) {
                    triggers.add(EducationCardTrigger.GRAPH_EDGE);
                }
                if (sample.value() == null || sample.flag() == ReadingFlag.MISSING) continue;
                if (sample.value() < 70) {
                    triggers.add(EducationCardTrigger.LOW_READING);
                    if (sample.time().atZone(KST).getHour() < 6) triggers.add(EducationCardTrigger.NIGHT_LOW);
                }
            }
        });
        if (episodes.stream().anyMatch(episode -> Boolean.TRUE.equals(episode.reboundDetected()))) {
            triggers.add(EducationCardTrigger.REBOUND);
        }
        // 묶인 에피소드의 대표 맥락은 중간의 술/처치 기록을 놓칠 수 있어 원래 섭취 기록을 확인한다.
        intakeRepository.findByUserIdAndOccurredAtGreaterThanEqualAndOccurredAtLessThan(userId,
                date.atStartOfDay(KST).toInstant(), date.plusDays(1).atStartOfDay(KST).toInstant())
                .forEach(intake -> {
                    if (intake.getContext() == PhotoContext.HYPO_TREATMENT) triggers.add(EducationCardTrigger.HYPO_TREATED);
                    if (intake.getContext() == PhotoContext.ALCOHOL) triggers.add(EducationCardTrigger.ALCOHOL);
                });
        if (triggers.isEmpty()) return List.of();
        return repository.findByPlacementAndApprovedTrueOrderBySortOrderAscCodeAsc(EducationCardPlacement.DAILY)
                .stream().filter(card -> card.getTrigger() != null && triggers.contains(card.getTrigger()))
                .map(EducationCardResponse::from).toList();
    }
}
