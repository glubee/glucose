package com.glucoselog.glucose;

/** 1.0 계열의 좌표 보정 오류 및 이전 버전의 데이터/날짜 문제를 수정한 최소 버전. */
public final class GraphParserVersion {
    public static final String MINIMUM_SUPPORTED = "1.1.4";

    private GraphParserVersion() { }

    /** 쓰기 전 검증 실패다. 워커가 실패 상태를 저장할 트랜잭션까지 rollback-only로 만들지 않는다. */
    public static final class UnsupportedVersionException extends Exception {
        public UnsupportedVersionException() {
            super("GRAPH_PARSER_OUTDATED: 지원하지 않는 그래프 분석기 버전입니다");
        }
    }

    public static boolean isSupported(String version) {
        if (version == null || !version.matches("\\d+\\.\\d+\\.\\d+")) return false;
        try {
            String[] actual = version.split("\\.");
            String[] required = MINIMUM_SUPPORTED.split("\\.");
            for (int i = 0; i < 3; i++) {
                int comparison = Integer.compare(Integer.parseInt(actual[i]), Integer.parseInt(required[i]));
                if (comparison != 0) return comparison > 0;
            }
            return true;
        } catch (NumberFormatException e) {
            return false;
        }
    }
}
