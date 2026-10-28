package com.glucoselog.glucose;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;

public interface GlucoseGraphUploadRepository extends JpaRepository<GlucoseGraphUpload, UUID> {

    Optional<GlucoseGraphUpload> findByIdAndUserId(UUID id, UUID userId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT u FROM GlucoseGraphUpload u WHERE u.id = :id AND u.userId = :userId")
    Optional<GlucoseGraphUpload> findOwnedForUpdate(@Param("id") UUID id, @Param("userId") UUID userId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT u FROM GlucoseGraphUpload u WHERE u.userId = :userId AND u.resultDate = :date")
    Optional<GlucoseGraphUpload> findOwnedDateForUpdate(@Param("userId") UUID userId, @Param("date") LocalDate date);

    Optional<GlucoseGraphUpload> findByUserIdAndResultDate(UUID userId, LocalDate resultDate);

    List<GlucoseGraphUpload> findByUserIdAndResultDateAndIdNot(UUID userId, LocalDate resultDate, UUID excludedId);

    @Query("SELECT u.parseJobId FROM GlucoseGraphUpload u WHERE u.userId = :userId AND u.parseJobId IS NOT NULL")
    List<UUID> findParseJobIdsByUserId(@Param("userId") UUID userId);
}
