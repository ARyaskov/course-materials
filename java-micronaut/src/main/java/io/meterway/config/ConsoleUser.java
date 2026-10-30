package io.meterway.config;

import io.micronaut.context.annotation.EachProperty;
import io.micronaut.context.annotation.Parameter;
import jakarta.validation.constraints.NotBlank;

import java.util.List;

/**
 * Учётная запись оператора панели, объявленная в конфигурации.
 * Секция {@code meterway.console.users.<login>} превращается в отдельный бин.
 */
@EachProperty("meterway.console.users")
public class ConsoleUser {

    private final String username;

    @NotBlank
    private String passwordHash;

    @NotBlank
    private String tenantId;

    private List<String> roles = List.of("CONSOLE");

    public ConsoleUser(@Parameter String username) {
        this.username = username;
    }

    public String getUsername() {
        return username;
    }

    public String getPasswordHash() {
        return passwordHash;
    }

    public void setPasswordHash(String passwordHash) {
        this.passwordHash = passwordHash;
    }

    public String getTenantId() {
        return tenantId;
    }

    public void setTenantId(String tenantId) {
        this.tenantId = tenantId;
    }

    public List<String> getRoles() {
        return roles;
    }

    public void setRoles(List<String> roles) {
        this.roles = roles;
    }
}
