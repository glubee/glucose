package com.glucoselog.config;

import java.time.Clock;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.glucoselog.report.ReportProperties;
import com.glucoselog.report.ReportNarrationProperties;
import com.glucoselog.report.FoodObservationProperties;

@Configuration
@EnableConfigurationProperties({ReportProperties.class, ReportNarrationProperties.class, FoodObservationProperties.class})
public class ReportConfig {

    /** "오늘"을 판단하는 시계. 테스트에서 고정 시계로 바꿀 수 있게 빈으로 둔다. */
    @Bean
    Clock clock() {
        return Clock.systemUTC();
    }
}
