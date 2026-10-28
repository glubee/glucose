package com.glucoselog.report;

import java.util.List;

/**
 * 흐름 안내 한 건(DailyInsightDetector). 코드가 찾은 흐름에 미리 써 둔 일반 안내를 붙인 것이다.
 * reviewStatus가 DRAFT면 의료인 검토 전 문구다. priority는 작을수록 먼저 보여준다.
 */
public record ReportInsight(String code, int priority, String title, String body, List<Source> sources, String reviewStatus) {

    public record Source(String name, String url) {
    }

    public ReportInsight(String code, int priority, String title, String body, List<Source> sources) {
        this(code, priority, title, body, sources, "DRAFT");
    }
}
