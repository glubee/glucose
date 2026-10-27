package com.glucoselog.report;

import java.time.LocalDate;
import java.util.UUID;

import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/v1/reports")
public class ReportController {

    private final DailyReportService dailyReportService;
    private final WeeklyReportService weeklyReportService;
    private final ClinicianReportService clinicianReportService;
    private final ReportNarrationService narrationService;
    private final FoodObservationService foodObservationService;

    public ReportController(
            DailyReportService dailyReportService,
            WeeklyReportService weeklyReportService,
            ClinicianReportService clinicianReportService,
            ReportNarrationService narrationService,
            FoodObservationService foodObservationService) {
        this.dailyReportService = dailyReportService;
        this.weeklyReportService = weeklyReportService;
        this.clinicianReportService = clinicianReportService;
        this.narrationService = narrationService;
        this.foodObservationService = foodObservationService;
    }

    @GetMapping("/daily/{date}")
    public DailyReportResponse daily(@PathVariable LocalDate date, Authentication authentication) {
        return dailyReportService.getDailyReport(userId(authentication), date);
    }

    @GetMapping("/weekly/{date}")
    public WeeklyReportResponse weekly(@PathVariable LocalDate date, Authentication authentication) {
        return weeklyReportService.getWeeklyReport(userId(authentication), date);
    }

    @GetMapping("/daily/{date}/food-observations")
    public FoodObservationResponse dailyFoodObservations(@PathVariable LocalDate date, Authentication authentication) {
        return foodObservationService.daily(userId(authentication), date);
    }

    @GetMapping("/weekly/{date}/food-observations")
    public FoodObservationResponse weeklyFoodObservations(@PathVariable LocalDate date, Authentication authentication) {
        return foodObservationService.weekly(userId(authentication), date);
    }

    @PostMapping("/daily/{date}/narrative")
    public ReportNarrativeResponse dailyNarrative(@PathVariable LocalDate date, Authentication authentication) {
        return narrationService.daily(dailyReportService.getDailyReport(userId(authentication), date));
    }

    @PostMapping("/weekly/{date}/narrative")
    public ReportNarrativeResponse weeklyNarrative(@PathVariable LocalDate date, Authentication authentication) {
        return narrationService.weekly(weeklyReportService.getWeeklyReport(userId(authentication), date));
    }

    /** 의료인 공유용. 기간은 from~to(양끝 포함, 한국 시간 날짜), 최대 31일. */
    @GetMapping("/clinician")
    public ClinicianReportResponse clinician(
            @RequestParam LocalDate from, @RequestParam LocalDate to, Authentication authentication) {
        return clinicianReportService.getReport(userId(authentication), from, to);
    }

    private static UUID userId(Authentication authentication) {
        return (UUID) authentication.getPrincipal();
    }
}
