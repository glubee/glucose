package com.glucoselog.report;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "report.narration")
public record ReportNarrationProperties(boolean enabled, long timeoutMs) {}
