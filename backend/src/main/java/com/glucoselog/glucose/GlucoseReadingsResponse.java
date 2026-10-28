package com.glucoselog.glucose;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record GlucoseReadingsResponse(LocalDate date, BigDecimal coverageRatio, List<ReadingResponse> readings,
        UUID uploadId, String parserVersion) {

    public record ReadingResponse(String time, Integer value, ReadingFlag flag) {
    }
}
