package com.glucoselog.report;

/** APP_GUIDE는 앱 내 분석 안내로 연결하며 외부 의학 출처로 표시하지 않는다. */
public record EducationCardSource(String name, String url, String kind) {
}
