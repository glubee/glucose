package com.glucoselog.report;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import com.glucoselog.episode.EpisodeProperties;
import com.glucoselog.insulin.InsulinEventRepository;
import com.glucoselog.intake.*;
import com.glucoselog.photo.PhotoContext;

class FoodObservationServiceTest {
    @Test void queries_authenticated_user_with_cross_day_context_and_uses_latest_food_names() {
        UUID user=UUID.randomUUID();
        LocalDate date=LocalDate.of(2026,10,19);
        var repo=mock(IntakeRepository.class);var insulin=mock(InsulinEventRepository.class);
        var timeline=mock(GlucoseTimelineService.class);var item=mock(IntakeItem.class);
        var record=new Intake(user,null,PhotoContext.MEAL,FoodObservationAnalyzerTest.at(date,"09:00"));
        record.replaceItems(List.of(item));
        when(item.getName()).thenReturn("수정한 음식명");
        when(repo.findForFoodReport(eq(user),any(),any())).thenReturn(List.of(record));
        when(insulin.findByUserIdAndOccurredAtGreaterThanEqualAndOccurredAtLessThan(eq(user),any(),any())).thenReturn(List.of());
        when(timeline.loadRange(eq(user),any(),any())).thenReturn(FoodObservationAnalyzerTest.samples(record.getOccurredAt(),150));
        var windows=new EpisodeProperties(90,4,2,12,70);var properties=new FoodObservationProperties(15,2,2);
        var service=new FoodObservationService(repo,insulin,timeline,new FoodObservationAnalyzerTest().analyzer,windows,properties,
                Clock.fixed(FoodObservationAnalyzerTest.NOW,ZoneOffset.UTC));
        var result=service.daily(user,date);
        assertThat(result.observations().getFirst().foods().getFirst().name()).isEqualTo("수정한 음식명");
        var from=ArgumentCaptor.forClass(Instant.class);var to=ArgumentCaptor.forClass(Instant.class);
        verify(repo).findForFoodReport(eq(user),from.capture(),to.capture());
        assertThat(from.getValue()).isBefore(FoodObservationAnalyzerTest.at(date,"00:00"));
        assertThat(to.getValue()).isAfter(FoodObservationAnalyzerTest.at(date.plusDays(1),"00:00"));
        verify(timeline).loadRange(user,date.minusDays(1),date.plusDays(1));
        when(item.getName()).thenReturn("다시 수정한 이름");
        assertThat(service.daily(user,date).observations().getFirst().foods().getFirst().name()).isEqualTo("다시 수정한 이름");
        assertThat(service.weekly(user,date.plusDays(3)).from()).isEqualTo(date);
        assertThat(service.weekly(user,date.plusDays(3)).to()).isEqualTo(date.plusDays(6));
        when(repo.findForFoodReport(eq(user),any(),any())).thenReturn(List.of());
        assertThat(service.daily(user,date).observations()).isEmpty();
    }
}
