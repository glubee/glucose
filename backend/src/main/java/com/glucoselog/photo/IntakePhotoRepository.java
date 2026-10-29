package com.glucoselog.photo;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.Lock;
import jakarta.persistence.LockModeType;
import java.time.Instant;

public interface IntakePhotoRepository extends JpaRepository<IntakePhoto, UUID> {

    Optional<IntakePhoto> findByIdAndUserId(UUID id, UUID userId);
    Optional<IntakePhoto> findByUserIdAndClientId(UUID userId, UUID clientId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from IntakePhoto p where p.id = :id and p.userId = :userId")
    Optional<IntakePhoto> findLocked(@Param("id") UUID id, @Param("userId") UUID userId);

    @Query(value = "select * from intake_photo where user_id = :userId and status = 'UPLOADED' "
            + "and confirmed_at is null and dismissed_at is null order by coalesce(captured_at, created_at) desc, id desc", nativeQuery = true)
    List<IntakePhoto> pending(@Param("userId") UUID userId, Pageable pageable);

    @Query(value = "select * from intake_photo where user_id = :userId and status = 'UPLOADED' "
            + "and confirmed_at is null and dismissed_at is null "
            + "and (coalesce(captured_at, created_at) < :time or (coalesce(captured_at, created_at) = :time and id < :id)) "
            + "order by coalesce(captured_at, created_at) desc, id desc", nativeQuery = true)
    List<IntakePhoto> pendingAfter(@Param("userId") UUID userId, @Param("time") Instant time, @Param("id") UUID id, Pageable pageable);

    @Query("SELECT p.recognitionJobId FROM IntakePhoto p WHERE p.userId = :userId AND p.recognitionJobId IS NOT NULL")
    List<UUID> findRecognitionJobIdsByUserId(@Param("userId") UUID userId);
}
