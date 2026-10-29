package com.glucoselog.photo;

import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestParam;
import com.glucoselog.common.PageResponse;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/v1/photos")
public class PhotoController {

    private final PhotoUploadService photoUploadService;

    public PhotoController(PhotoUploadService photoUploadService) {
        this.photoUploadService = photoUploadService;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public PhotoUploadResponse startUpload(
            @Valid @RequestBody StartPhotoUploadRequest request, Authentication authentication) {
        UUID userId = (UUID) authentication.getPrincipal();
        return photoUploadService.startUpload(userId, request.contentType(), request.context(), request.capturedAt(), request.clientId());
    }

    @GetMapping
    public PageResponse<PhotoMetadata> pending(@RequestParam(defaultValue = "true") boolean unconfirmed,
            @RequestParam(required = false) String cursor, @RequestParam(defaultValue = "20") int limit,
            Authentication authentication) {
        return photoUploadService.pending((UUID) authentication.getPrincipal(), cursor, limit);
    }

    @GetMapping("/{photoId}")
    public PhotoMetadata metadata(@PathVariable UUID photoId, Authentication auth) {
        return photoUploadService.metadata((UUID) auth.getPrincipal(), photoId);
    }

    @PatchMapping("/{photoId}/metadata")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void updateMetadata(@PathVariable UUID photoId, @Valid @RequestBody PhotoMetadataRequest request, Authentication auth) {
        photoUploadService.updateMetadata((UUID) auth.getPrincipal(), photoId, request);
    }

    @PostMapping("/{photoId}/dismiss")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void dismiss(@PathVariable UUID photoId, Authentication auth) {
        photoUploadService.dismiss((UUID) auth.getPrincipal(), photoId);
    }

    @GetMapping("/{photoId}/view")
    public PhotoViewResponse view(@PathVariable UUID photoId, Authentication authentication) {
        UUID userId = (UUID) authentication.getPrincipal();
        return photoUploadService.viewUrl(userId, photoId);
    }

    @PostMapping("/{photoId}/complete")
    public ResponseEntity<Void> completeUpload(@PathVariable UUID photoId, Authentication authentication) {
        UUID userId = (UUID) authentication.getPrincipal();
        photoUploadService.completeUpload(userId, photoId);
        return ResponseEntity.noContent().build();
    }
}
