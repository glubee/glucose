package com.glucoselog.photo;

import java.net.URL;
import java.time.Instant;
import java.util.Map;
import java.util.List;
import org.springframework.data.domain.PageRequest;
import com.glucoselog.common.PageResponse;
import com.glucoselog.auth.AppUserRepository;
import java.util.Set;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.glucoselog.common.ApiException;
import com.glucoselog.job.Job;
import com.glucoselog.job.JobService;

@Service
public class PhotoUploadService {

    private static final Set<String> ALLOWED_CONTENT_TYPES = Set.of("image/jpeg", "image/png");

    private final IntakePhotoRepository repository;
    private final AppUserRepository users;
    private final PhotoStorageService storageService;
    private final R2Properties properties;
    private final JobService jobService;

    public PhotoUploadService(
            IntakePhotoRepository repository,
            AppUserRepository users,
            PhotoStorageService storageService,
            R2Properties properties,
            JobService jobService) {
        this.repository = repository;
        this.users = users;
        this.storageService = storageService;
        this.properties = properties;
        this.jobService = jobService;
    }

    @Transactional
    public PhotoUploadResponse startUpload(UUID userId, String contentType, PhotoContext context, Instant capturedAt, UUID clientId) {
        lockUser(userId);
        if (!ALLOWED_CONTENT_TYPES.contains(contentType)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "지원하지 않는 이미지 형식입니다 (JPEG/PNG만 가능)");
        }

        IntakePhoto photo = clientId == null ? null : repository.findByUserIdAndClientId(userId, clientId).orElse(null);
        if (photo != null && photo.isDismissed()) {
            throw new ApiException(HttpStatus.CONFLICT, "PHOTO_DISMISSED", "이미 대기 목록에서 정리한 사진입니다");
        }
        if (photo == null) {
            String objectKey = "photos/%s/%s.%s".formatted(userId, UUID.randomUUID(), extensionOf(contentType));
            photo = new IntakePhoto(userId, objectKey, contentType, context);
            photo.restoreMetadata(capturedAt, clientId, context);
            repository.save(photo);
        }
        URL uploadUrl = storageService.presignPut(photo.getObjectKey(), photo.getContentType());
        return new PhotoUploadResponse(photo.getId(), uploadUrl.toString(), photo.getObjectKey(), properties.presignTtlSeconds(),
                photo.getStatus() == PhotoStatus.UPLOADED);
    }

    /** 본인 사진만, 업로드가 끝난 사진만 보기 주소를 준다 */
    @Transactional(readOnly = true)
    public PhotoViewResponse viewUrl(UUID userId, UUID photoId) {
        IntakePhoto photo = repository.findByIdAndUserId(photoId, userId)
                .filter(p -> p.getStatus() == PhotoStatus.UPLOADED)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "PHOTO_NOT_FOUND", "사진을 찾을 수 없습니다"));
        return new PhotoViewResponse(storageService.presignGet(photo.getObjectKey()).toString(), properties.presignTtlSeconds());
    }

    @Transactional
    public void completeUpload(UUID userId, UUID photoId) {
        lockUser(userId);
        IntakePhoto photo = ownedLocked(userId, photoId);
        if (photo.isDismissed()) throw new ApiException(HttpStatus.CONFLICT, "PHOTO_DISMISSED", "이미 대기 목록에서 정리한 사진입니다");

        if (photo.getStatus() == PhotoStatus.UPLOADED) {
            return; // 이미 완료 처리됨 (멱등)
        }
        if (!storageService.exists(photo.getObjectKey())) {
            throw new ApiException(HttpStatus.CONFLICT, "PHOTO_NOT_UPLOADED", "업로드가 아직 완료되지 않았습니다");
        }

        photo.markUploaded(Instant.now());

        // ml-service 호출은 워커가 비동기로 처리한다 — 이 요청 스레드는 기다리지 않는다.
        Job job = jobService.enqueue(FoodRecognizeJobHandler.JOB_TYPE, Map.of("photo_id", photo.getId().toString()));
        photo.setRecognitionJobId(job.getId());
        repository.save(photo);
    }

    @Transactional(readOnly = true)
    public PageResponse<PhotoMetadata> pending(UUID userId, String cursor, int limit) {
        if (limit < 1 || limit > 100) throw new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "limit는 1~100입니다");
        PhotoCursor after = cursor == null ? null : PhotoCursor.decode(cursor);
        List<IntakePhoto> page = after == null ? repository.pending(userId, PageRequest.of(0, limit))
                : repository.pendingAfter(userId, after.time(), after.id(), PageRequest.of(0, limit));
        return new PageResponse<>(page.stream().map(PhotoMetadata::from).toList(),
                page.size() == limit ? PhotoCursor.encode(page.get(page.size() - 1)) : null);
    }

    @Transactional(readOnly = true)
    public PhotoMetadata metadata(UUID userId, UUID photoId) {
        return PhotoMetadata.from(repository.findByIdAndUserId(photoId, userId).orElseThrow(PhotoUploadService::notFound));
    }

    @Transactional
    public void updateMetadata(UUID userId, UUID photoId, PhotoMetadataRequest request) {
        lockUser(userId);
        IntakePhoto photo = ownedLocked(userId, photoId);
        if (request.clientId() != null) {
            IntakePhoto existing = repository.findByUserIdAndClientId(userId, request.clientId()).orElse(null);
            if (existing != null && !existing.getId().equals(photoId)) {
                throw new ApiException(HttpStatus.CONFLICT, "PHOTO_CLIENT_ID_REUSED", "사진 식별자가 다른 사진에 사용되었습니다");
            }
        }
        photo.restoreMetadata(request.capturedAt(), request.clientId(), request.context());
    }

    @Transactional
    public void dismiss(UUID userId, UUID photoId) {
        lockUser(userId);
        ownedLocked(userId, photoId).dismiss();
    }

    @Transactional
    public void confirmForIntake(UUID userId, UUID photoId) {
        lockUser(userId);
        IntakePhoto photo = ownedLocked(userId, photoId);
        if (photo.getStatus() != PhotoStatus.UPLOADED) {
            throw new ApiException(HttpStatus.CONFLICT, "PHOTO_NOT_UPLOADED", "업로드가 아직 완료되지 않았습니다");
        }
        photo.confirm();
    }

    private IntakePhoto ownedLocked(UUID userId, UUID id) {
        return repository.findLocked(id, userId).orElseThrow(PhotoUploadService::notFound);
    }
    private void lockUser(UUID userId) {
        users.findLocked(userId).orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "로그인이 필요합니다"));
    }
    private static ApiException notFound() { return new ApiException(HttpStatus.NOT_FOUND, "PHOTO_NOT_FOUND", "사진을 찾을 수 없습니다"); }

    private static String extensionOf(String contentType) {
        return "image/png".equals(contentType) ? "png" : "jpg";
    }
}
