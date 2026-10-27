package com.glucoselog.report;

import java.util.List;

public record ReportNarrativeResponse(
        String kind, String source, List<Paragraph> paragraphs,
        List<NarrativeFact> facts, List<String> limitations) {
    public record Paragraph(String text, List<String> factIds) {}
}
