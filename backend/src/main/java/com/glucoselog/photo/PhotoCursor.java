package com.glucoselog.photo;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import com.glucoselog.common.ApiException;
record PhotoCursor(Instant time, UUID id) {
    static String encode(IntakePhoto photo) {
        String raw = photo.getCapturedAt() + "|" + photo.getId();
        return Base64.getUrlEncoder().withoutPadding().encodeToString(raw.getBytes(StandardCharsets.UTF_8));
    }
    static PhotoCursor decode(String value) {
        try {
            String raw = new String(Base64.getUrlDecoder().decode(value), StandardCharsets.UTF_8);
            int split = raw.indexOf('|');
            return new PhotoCursor(Instant.parse(raw.substring(0, split)), UUID.fromString(raw.substring(split + 1)));
        } catch (RuntimeException exception) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "cursor 값이 올바르지 않습니다");
        }
    }
}
