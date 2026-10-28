package com.glucoselog.report;

import java.time.LocalDate;
import java.util.List;

public record EducationCardResponse(
        String code, EducationCardTrigger trigger, String title, String body,
        List<EducationCardSource> sources, String reviewedBy, LocalDate reviewedAt, String reviewType) {

    static EducationCardResponse from(EducationCard card) {
        return new EducationCardResponse(card.getCode(), card.getTrigger(), card.getTitle(), card.getBody(),
                card.getSources(), card.getReviewedBy(), card.getReviewedAt(), card.getReviewType());
    }
}
