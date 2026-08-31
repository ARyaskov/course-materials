package com.example.taskflow.task;

import com.example.taskflow.common.exception.ResourceNotFoundException;
import com.example.taskflow.project.Project;
import com.example.taskflow.project.ProjectRepository;
import com.example.taskflow.user.User;
import com.example.taskflow.user.UserRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class TaskServiceTest {

    @Mock TaskRepository taskRepository;
    @Mock ProjectRepository projectRepository;
    @Mock UserRepository userRepository;
    @InjectMocks TaskService taskService;

    @Test
    void createTask_whenProjectAndUserExist_returnsResponse() {
        var creator = new User("alice", "alice@example.com", "hash");
        var project = new Project("Demo", creator);
        var request = new CreateTaskRequest("Deploy", "to staging", 1L, null, null);

        when(projectRepository.findById(1L)).thenReturn(Optional.of(project));
        when(userRepository.findById(1L)).thenReturn(Optional.of(creator));
        when(taskRepository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

        var response = taskService.createTask(1L, request);

        assertThat(response.title()).isEqualTo("Deploy");
        assertThat(response.status()).isEqualTo("TODO");
        assertThat(response.priority()).isEqualTo("MEDIUM");
    }

    @Test
    void createTask_whenProjectMissing_throwsNotFound() {
        var request = new CreateTaskRequest("Deploy", null, 99L, null, null);

        when(projectRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> taskService.createTask(1L, request))
                .isInstanceOf(ResourceNotFoundException.class)
                .hasMessageContaining("Project not found");

        verify(taskRepository, never()).save(any());
    }
}
