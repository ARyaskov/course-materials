package beacon.error;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.util.List;

/**
 * Единый формат ошибки API v1. Фиксируется один раз и не меняется:
 * клиенты разбирают {@code code}, люди читают {@code message}.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ApiError(String code, String message, String requestId, List<FieldError> fields) {

    public record FieldError(String field, String message) {}

    public static ApiError of(String code, String message, String requestId) {
        return new ApiError(code, message, requestId, null);
    }

    public static ApiError validation(String message, String requestId, List<FieldError> fields) {
        return new ApiError("validation_failed", message, requestId, fields);
    }
}
