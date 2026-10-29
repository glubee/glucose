package com.glucoselog.progress;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.glucoselog.common.ApiException;

@Service
public class ProgressSyncService {
    private final ProgressAccountRepository accounts;
    private final ProgressCommandRepository commands;
    private final JdbcTemplate jdbc;
    private final ObjectMapper json;

    public record Response(long revision, DayCloseState state, List<UUID> acknowledgedOperations) {}

    public ProgressSyncService(ProgressAccountRepository accounts, ProgressCommandRepository commands,
                               JdbcTemplate jdbc, ObjectMapper json) {
        this.accounts = accounts; this.commands = commands; this.jdbc = jdbc; this.json = json;
    }

    @Transactional
    public Response read(UUID userId) { return sync(userId, null, List.of()); }

    @Transactional
    public Response sync(UUID userId, DayCloseState legacy, List<ProgressOperation> operations) {
        jdbc.update("INSERT INTO progress_account(user_id) SELECT id FROM app_user WHERE id = ? ON CONFLICT DO NOTHING", userId);
        ProgressAccount account = accounts.findLocked(userId)
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "로그인이 필요합니다"));
        try {
            DayCloseState state = json.readValue(account.getStateJson(), DayCloseState.class);
            LocalDateTime now = LocalDateTime.now(ZoneId.of("Asia/Seoul"));
            if (legacy != null) {
                legacy.validate(now.toLocalDate());
                if (!account.isInitialized()) state = legacy;
                else state.mergeHistory(legacy);
            }
            List<UUID> acknowledged = new ArrayList<>();
            for (ProgressOperation operation : operations) {
                String payload = json.writeValueAsString(operation);
                String hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                        .digest(payload.getBytes(StandardCharsets.UTF_8)));
                ProgressCommand existing = commands.findByUserIdAndOperationId(userId, operation.id()).orElse(null);
                if (existing != null) {
                    if (!existing.getPayloadHash().equals(hash)) {
                        throw new ApiException(HttpStatus.CONFLICT, "OPERATION_ID_REUSED", "변경 식별자가 다른 내용으로 재사용되었습니다");
                    }
                } else {
                    state.apply(operation, now);
                    commands.save(new ProgressCommand(userId, operation.id(), hash));
                }
                acknowledged.add(operation.id());
            }
            // Offline completions must land before deciding which missing days need protection.
            state.applyHoneypots(now);
            String saved = json.writeValueAsString(state);
            if (!saved.equals(account.getStateJson())) account.replace(saved, account.isInitialized() || state.hasData());
            return new Response(account.getRevision(), state, acknowledged);
        } catch (IllegalArgumentException | java.time.DateTimeException exception) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "완료 상태와 날짜를 확인해 주세요");
        } catch (ApiException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new IllegalStateException("진행 상태를 처리하지 못했습니다", exception);
        }
    }
}
