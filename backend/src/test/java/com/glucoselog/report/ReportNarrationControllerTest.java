package com.glucoselog.report;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

import java.time.LocalDate;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;

class ReportNarrationControllerTest {
    @Test
    void builds_daily_and_weekly_facts_from_the_authenticated_user_not_client_numbers() {
        var daily=mock(DailyReportService.class);
        var weekly=mock(WeeklyReportService.class);
        var narrative=mock(ReportNarrationService.class);
        var controller=new ReportController(daily,weekly,mock(ClinicianReportService.class),narrative,mock(FoodObservationService.class));
        UUID user=UUID.randomUUID();
        var authentication=new UsernamePasswordAuthenticationToken(user,null);
        var date=LocalDate.of(2026,10,1);
        var day=mock(DailyReportResponse.class);
        var week=mock(WeeklyReportResponse.class);
        when(daily.getDailyReport(eq(user),eq(date))).thenReturn(day);
        when(weekly.getWeeklyReport(eq(user),eq(date))).thenReturn(week);
        controller.dailyNarrative(date,authentication);
        controller.weeklyNarrative(date,authentication);
        verify(narrative).daily(day);
        verify(narrative).weekly(week);
        verifyNoMoreInteractions(narrative);
    }
}
