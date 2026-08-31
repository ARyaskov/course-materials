package com.example.taskflow.user;

import com.example.taskflow.common.exception.ResourceNotFoundException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.Optional;

@Service
public class UserService {

    private final UserRepository userRepository;

    public UserService(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    // Создание пользователя выполняется через регистрацию
    // (см. com.example.taskflow.security.AuthService).

    // READ
    @Transactional(readOnly = true)
    public Optional<User> findById(Long id) {
        return userRepository.findById(id);
    }

    @Transactional(readOnly = true)
    public User getById(Long id) {
        return userRepository.findById(id)
                .orElseThrow(() -> ResourceNotFoundException.ofUser(id));
    }

    // UPDATE
    @Transactional
    public User updateDisplayName(Long id, String displayName) {
        var user = getById(id);
        user.setDisplayName(displayName);
        return userRepository.save(user);
    }

    // DELETE
    @Transactional
    public void deleteUser(Long id) {
        if (!userRepository.existsById(id)) {
            throw ResourceNotFoundException.ofUser(id);
        }
        userRepository.deleteById(id);
    }
}
