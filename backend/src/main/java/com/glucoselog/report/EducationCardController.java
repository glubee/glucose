package com.glucoselog.report;

import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/v1/education-cards")
public class EducationCardController {
    private final EducationCardService service;

    public EducationCardController(EducationCardService service) { this.service = service; }

    @GetMapping("/review")
    public List<EducationCardResponse> review() { return service.reviewCards(); }
}
