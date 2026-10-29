package com.glucoselog.progress;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProgressCommandRepository extends JpaRepository<ProgressCommand, UUID> {
    Optional<ProgressCommand> findByUserIdAndOperationId(UUID userId, UUID operationId);
}
