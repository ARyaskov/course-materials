// common/InfoController.java
package com.example.taskflow.common;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import java.time.Instant;

@RestController
@RequestMapping("/api/v1")
public class InfoController {

    record AppInfo(String name, String version, Instant serverTime) {}

    @GetMapping("/info")
    public AppInfo info() {
        return new AppInfo("TaskFlow API", "0.0.1", Instant.now());
    }
}
