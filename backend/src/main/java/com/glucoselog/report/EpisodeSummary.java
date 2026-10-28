package com.glucoselog.report;

import java.time.Instant;
import java.util.List;

import com.glucoselog.photo.PhotoContext;

/**
 * {@code autoReclassified}/{@code reboundDetected}가 {@code null}이면 "판단 불가"다 - 확인해봤는데
 * 아니라는 뜻(false)이 아니라, 그 시점에 쓸 글루코스 데이터가 없어서 확인 자체를 못 했다는 뜻이다.
 * {@code foods}는 묶음 안 섭취 기록의 음식 이름(+개수·단위), 기록 순서대로. 예: "짜장면 1그릇".
 */
public record EpisodeSummary(
        Instant startAt,
        PhotoContext originalContext,
        PhotoContext effectiveContext,
        Boolean autoReclassified,
        Instant windowEndAt,
        Boolean reboundDetected,
        int intakeCount,
        List<String> foods) {

    public EpisodeSummary {
        foods = foods == null ? List.of() : List.copyOf(foods);
    }

    public EpisodeSummary(Instant startAt, PhotoContext originalContext, PhotoContext effectiveContext,
            Boolean autoReclassified, Instant windowEndAt, Boolean reboundDetected, int intakeCount) {
        this(startAt, originalContext, effectiveContext, autoReclassified, windowEndAt, reboundDetected, intakeCount, List.of());
    }
}
