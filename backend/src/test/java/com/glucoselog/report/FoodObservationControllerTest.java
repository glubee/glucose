package com.glucoselog.report;

import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.fasterxml.jackson.databind.SerializationFeature;

class FoodObservationControllerTest {
    @Test void daily_and_weekly_routes_serialize_traceable_food_observations_for_the_authenticated_user() throws Exception {
        var user=UUID.randomUUID();
        var date=FoodObservationAnalyzerTest.MONDAY;
        var intake=FoodObservationAnalyzerTest.meal(date,"09:00",FoodObservationAnalyzerTest.food("김밥"));
        var analysis=new FoodObservationAnalyzerTest().analyzer;
        var daily=analysis.analyze("DAILY",date,date,List.of(intake),FoodObservationAnalyzerTest.samples(intake.time(),150),List.of(),FoodObservationAnalyzerTest.NOW);
        var weekly=analysis.analyze("WEEKLY",date,date.plusDays(6),List.of(intake),FoodObservationAnalyzerTest.samples(intake.time(),150),List.of(),FoodObservationAnalyzerTest.NOW);
        var service=mock(FoodObservationService.class);
        when(service.daily(user,date)).thenReturn(daily);
        when(service.weekly(user,date)).thenReturn(weekly);
        var controller=new ReportController(mock(DailyReportService.class),mock(WeeklyReportService.class),
                mock(ClinicianReportService.class),mock(ReportNarrationService.class),service);
        var mapper=new ObjectMapper().findAndRegisterModules().setPropertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)
                .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
        var mvc=MockMvcBuilders.standaloneSetup(controller)
                .setMessageConverters(new MappingJackson2HttpMessageConverter(mapper)).build();
        var principal=new UsernamePasswordAuthenticationToken(user,null);
        mvc.perform(get("/v1/reports/daily/2026-10-19/food-observations").principal(principal))
                .andExpect(status().isOk()).andExpect(jsonPath("$.kind").value("DAILY"))
                .andExpect(jsonPath("$.observations[0].intake_id").value(intake.id().toString()))
                .andExpect(jsonPath("$.observations[0].foods[0].name").value("김밥"))
                .andExpect(jsonPath("$.observations[0].peak_delta").value(50))
                .andExpect(jsonPath("$.observations[0].baseline.time").value("2026-10-19T00:00:00Z"));
        mvc.perform(get("/v1/reports/weekly/2026-10-19/food-observations").principal(principal))
                .andExpect(status().isOk()).andExpect(jsonPath("$.kind").value("WEEKLY"))
                .andExpect(jsonPath("$.from").value("2026-10-19"))
                .andExpect(jsonPath("$.to").value("2026-10-25"));
        verify(service).daily(user,date);
        verify(service).weekly(user,date);
    }
}
