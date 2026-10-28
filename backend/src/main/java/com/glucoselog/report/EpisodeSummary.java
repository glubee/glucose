package com.glucoselog.report;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.glucoselog.photo.PhotoContext;

/**
 * {@code autoReclassified}/{@code reboundDetected}가 {@code null}이면 "판단 불가"다 - 확인해봤는데
 * 아니라는 뜻(false)이 아니라, 그 시점에 쓸 글루코스 데이터가 없어서 확인 자체를 못 했다는 뜻이다.
 * {@code foods}는 묶음 안 섭취 기록의 음식 이름(+개수·단위), 기록 순서대로. 예: "짜장면 1그릇".
 * {@code intakes}는 묶음 안 섭취 기록 하나하나(정확한 시각·사진). 앱이 그래프에 기록 위치와 사진을 찍는 데 쓴다.
 */
public record EpisodeSummary(
        Instant startAt,
        PhotoContext originalContext,
        PhotoContext effectiveContext,
        Boolean autoReclassified,
        Instant windowEndAt,
        Boolean reboundDetected,
        int intakeCount,
        List<String> foods,
        List<IntakeMark> intakes) {

    /** 섭취 기록 한 건. photoId가 없으면 사진 없이 남긴 기록이다 */
    public record IntakeMark(Instant occurredAt, PhotoContext context, UUID photoId, List<String> foods) {
        public IntakeMark {
            foods = foods == null ? List.of() : List.copyOf(foods);
        }
    }

    public EpisodeSummary {
        foods = foods == null ? List.of() : List.copyOf(foods);
        intakes = intakes == null ? List.of() : List.copyOf(intakes);
    }

    public EpisodeSummary(Instant startAt, PhotoContext originalContext, PhotoContext effectiveContext,
            Boolean autoReclassified, Instant windowEndAt, Boolean reboundDetected, int intakeCount, List<String> foods) {
        this(startAt, originalContext, effectiveContext, autoReclassified, windowEndAt, reboundDetected, intakeCount, foods, List.of());
    }

    public EpisodeSummary(Instant startAt, PhotoContext originalContext, PhotoContext effectiveContext,
            Boolean autoReclassified, Instant windowEndAt, Boolean reboundDetected, int intakeCount) {
        this(startAt, originalContext, effectiveContext, autoReclassified, windowEndAt, reboundDetected, intakeCount, List.of(), List.of());
    }
}
