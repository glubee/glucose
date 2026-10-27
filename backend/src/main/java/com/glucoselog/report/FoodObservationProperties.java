package com.glucoselog.report;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix="report.food-observation")
public record FoodObservationProperties(int baselineMaxAgeMinutes, int minimumRepeatRecords, int minimumRepeatDays) {
    public FoodObservationProperties {
        if (baselineMaxAgeMinutes < 0 || minimumRepeatRecords < 2 || minimumRepeatDays < 2) {
            throw new IllegalArgumentException("Invalid food observation configuration");
        }
    }
}
