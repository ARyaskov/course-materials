package com.example.taskflow.security;

import com.example.taskflow.common.exception.ConflictException;
import com.example.taskflow.user.User;
import com.example.taskflow.user.UserRepository;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final AuthenticationManager authManager;

    public AuthService(UserRepository userRepository,
                       PasswordEncoder passwordEncoder,
                       JwtService jwtService,
                       AuthenticationManager authManager) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.authManager = authManager;
    }

    @Transactional
    public AuthResponse register(RegisterRequest request) {
        if (userRepository.existsByEmail(request.email())) {
            throw new ConflictException(
                "Email already registered: " + request.email());
        }
        if (userRepository.existsByUsername(request.username())) {
            throw new ConflictException(
                "Username already taken: " + request.username());
        }

        // Хешируем пароль перед сохранением
        var passwordHash = passwordEncoder.encode(request.password());
        var user = new User(request.username(), request.email(), passwordHash);
        var saved = userRepository.save(user);

        // Генерируем токен сразу после регистрации
        var token = jwtService.generateToken(saved.getId(), saved.getEmail());
        return new AuthResponse(token, saved.getId(), saved.getEmail());
    }

    public AuthResponse login(LoginRequest request) {
        // Spring Security проверит пароль через BCrypt
        authManager.authenticate(
            new UsernamePasswordAuthenticationToken(
                request.email(), request.password()));

        var user = userRepository.findByEmail(request.email()).orElseThrow();
        var token = jwtService.generateToken(user.getId(), user.getEmail());
        return new AuthResponse(token, user.getId(), user.getEmail());
    }
}
