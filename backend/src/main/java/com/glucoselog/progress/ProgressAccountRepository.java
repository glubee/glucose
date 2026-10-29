package com.glucoselog.progress;

import java.util.Optional;
import java.util.UUID;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;

public interface ProgressAccountRepository extends JpaRepository<ProgressAccount, UUID> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from ProgressAccount p where p.userId = :userId")
    Optional<ProgressAccount> findLocked(@Param("userId") UUID userId);
}
