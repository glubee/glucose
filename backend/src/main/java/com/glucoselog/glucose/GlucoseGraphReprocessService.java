package com.glucoselog.glucose;

import java.time.LocalDate;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.glucoselog.common.ApiException;
import com.glucoselog.job.Job;
import com.glucoselog.job.JobRepository;
import com.glucoselog.job.JobService;
import com.glucoselog.job.JobStatus;
import com.glucoselog.photo.PhotoStorageService;

@Service
public class GlucoseGraphReprocessService {
    private final GlucoseGraphUploadRepository uploads;
    private final JobRepository jobs;
    private final JobService jobService;
    private final PhotoStorageService storage;

    public GlucoseGraphReprocessService(GlucoseGraphUploadRepository uploads, JobRepository jobs,
            JobService jobService, PhotoStorageService storage) {
        this.uploads = uploads;
        this.jobs = jobs;
        this.jobService = jobService;
        this.storage = storage;
    }

    @Transactional
    public Response byDate(UUID userId, LocalDate date) {
        var upload = uploads.findOwnedDateForUpdate(userId, date)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "GLUCOSE_DAY_NOT_FOUND", "해당 날짜의 그래프가 없습니다"));
        return schedule(upload);
    }

    @Transactional
    public Response byId(UUID userId, UUID uploadId) {
        var upload = uploads.findOwnedForUpdate(uploadId, userId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "GLUCOSE_GRAPH_NOT_FOUND", "그래프를 찾을 수 없습니다"));
        return schedule(upload);
    }

    private Response schedule(GlucoseGraphUpload upload) {
        UUID uploadId = upload.getId();
        if (upload.getStatus() != GlucoseGraphUploadStatus.UPLOADED) {
            throw new ApiException(HttpStatus.CONFLICT, "GLUCOSE_GRAPH_NOT_UPLOADED", "원본 업로드가 완료되지 않았습니다");
        }
        Job current = upload.getParseJobId() == null ? null : jobs.findById(upload.getParseJobId()).orElse(null);
        if (current != null && (current.getStatus() == JobStatus.PENDING || current.getStatus() == JobStatus.PROCESSING)) {
            return new Response(uploadId);
        }
        if (!storage.exists(upload.getObjectKey())) {
            throw new ApiException(HttpStatus.NOT_FOUND, "GRAPH_SOURCE_NOT_FOUND", "저장된 원본 이미지가 없어 다시 업로드해야 합니다");
        }
        Job next = jobService.enqueue(GraphParseJobHandler.JOB_TYPE, Map.of("upload_id", uploadId.toString()));
        upload.setParseJobId(next.getId());
        uploads.save(upload);
        return new Response(uploadId);
    }

    public record Response(UUID uploadId) { }
}
