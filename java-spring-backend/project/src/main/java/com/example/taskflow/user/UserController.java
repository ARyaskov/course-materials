package com.example.taskflow.user;

import com.example.taskflow.security.SecurityUtils;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/users")
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    // GET /api/v1/users/me — профиль текущего пользователя
    @GetMapping("/me")
    public UserResponse me() {
        return UserResponse.from(userService.getById(SecurityUtils.currentUserId()));
    }

    // GET /api/v1/users/42
    @GetMapping("/{id}")
    public UserResponse getById(@PathVariable Long id) {
        return UserResponse.from(userService.getById(id));
    }

    // PATCH /api/v1/users/me — обновить отображаемое имя
    @PatchMapping("/me")
    public UserResponse updateDisplayName(@RequestBody @Valid UpdateDisplayNameRequest request) {
        var user = userService.updateDisplayName(
            SecurityUtils.currentUserId(), request.displayName());
        return UserResponse.from(user);
    }

    public record UpdateDisplayNameRequest(
        @NotBlank @Size(max = 100) String displayName
    ) {}
}
