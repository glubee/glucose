package com.glucoselog.photo;

/** 사진 보기용 짧은 GET 주소. 주소는 로그에 남기지 않는다. */
public record PhotoViewResponse(String url, long expiresIn) {
}
