package com.glucoselog.glucose;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * GraphParseJobHandler가 ml-service 응답을 받은 뒤 호출한다. 음식 인식과 달리 사용자가 수정·확정하는
 * 단계가 없다(OCR로 읽은 객관적인 값) - job이 끝나는 즉시 glucose_reading에 반영한다.
 * 같은 (user_id, result_date)에 대한 재업로드는 기존 걸 지우고 덮어쓴다(Dave 확인).
 */
@Service
public class GlucoseGraphParseService {

    private final GlucoseGraphUploadRepository uploadRepository;
    private final GlucoseReadingRepository readingRepository;
    private final ObjectMapper objectMapper;

    public GlucoseGraphParseService(
            GlucoseGraphUploadRepository uploadRepository,
            GlucoseReadingRepository readingRepository,
            ObjectMapper objectMapper) {
        this.uploadRepository = uploadRepository;
        this.readingRepository = readingRepository;
        this.objectMapper = objectMapper;
    }

    @Transactional
    public String apply(UUID uploadId, String rawJson) throws Exception {
        GraphParseResult result = objectMapper.readValue(rawJson, GraphParseResult.class);
        String parserVersion = result.meta() != null ? result.meta().parserVersion() : null;
        // 오래된 실행 이미지가 성공 응답을 내더라도 잘못된 수치를 저장하거나 기존 결과를 지우지 않는다.
        if (!GraphParserVersion.isSupported(parserVersion)) {
            throw new GraphParserVersion.UnsupportedVersionException();
        }
        GlucoseGraphUpload upload = uploadRepository.findById(uploadId)
                .orElseThrow(() -> new IllegalStateException("그래프 업로드를 찾을 수 없습니다: " + uploadId));

        LocalDate date = LocalDate.parse(result.date());

        // 덮어쓰기 정책: 같은 사용자의 같은 날짜로 이미 분석된 다른 업로드가 있으면 지운다(readings는 cascade로 같이 삭제됨).
        uploadRepository.findByUserIdAndResultDateAndIdNot(upload.getUserId(), date, uploadId)
                .forEach(uploadRepository::delete);

        // 재시도로 다시 들어온 경우를 대비해 이 업로드 자신의 기존 readings는 먼저 비운다.
        readingRepository.deleteByUploadId(uploadId);
        // Hibernate는 INSERT를 DELETE보다 먼저 보낼 수 있다. 같은 원본 재분석 시 시간 슬롯 충돌을 막는다.
        // 동일 트랜잭션이므로 새 결과 저장에 실패하면 기존 값도 함께 복원된다.
        readingRepository.flush();

        List<GlucoseReading> readings = result.readings().stream()
                .map(r -> new GlucoseReading(uploadId, toTimeSlot(r.time()), r.value(), ReadingFlag.valueOf(r.flag())))
                .toList();
        readingRepository.saveAll(readings);

        upload.applyParseResult(date, result.coverageRatio(), parserVersion);
        uploadRepository.save(upload);

        return objectMapper.writeValueAsString(new GlucoseGraphStatusResponse(date, result.coverageRatio(), parserVersion));
    }

    private static int toTimeSlot(String time) {
        return LocalTime.parse(time).toSecondOfDay() / 60;
    }
}
