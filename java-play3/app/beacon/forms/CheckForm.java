package beacon.forms;

import play.data.validation.Constraints;

/**
 * Форма создания проверки в админке.
 *
 * <p>{@code play.data} связывает поля напрямую, поэтому геттеры нужны шаблону, а не биндеру.
 * Аннотации {@link Constraints} — это Jakarta Bean Validation: те же ограничения работают
 * и при биндинге формы, и при валидации объекта вручную.
 */
@Constraints.Validate
public class CheckForm implements Constraints.Validatable<java.util.List<play.data.validation.ValidationError>> {

    @Constraints.Required
    @Constraints.Pattern("[a-z0-9][a-z0-9-]{0,62}")
    public String serviceKey;

    @Constraints.Required
    @Constraints.MaxLength(200)
    public String name;

    @Constraints.Required
    @Constraints.Pattern("GET|HEAD|POST")
    public String method = "GET";

    @Constraints.Required
    @Constraints.MaxLength(2000)
    public String url;

    @Constraints.Min(100)
    @Constraints.Max(599)
    public int expectedStatus = 200;

    @Constraints.MaxLength(500)
    public String bodyContains;

    @Constraints.Min(100)
    @Constraints.Max(60000)
    public int timeoutMs = 10000;

    @Constraints.Min(10)
    @Constraints.Max(86400)
    public int intervalSeconds = 60;

    /** Межполевая проверка: одного @Constraints тут недостаточно. */
    @Override
    public java.util.List<play.data.validation.ValidationError> validate() {
        var errors = new java.util.ArrayList<play.data.validation.ValidationError>();
        if (url != null && !(url.startsWith("http://") || url.startsWith("https://"))) {
            errors.add(new play.data.validation.ValidationError("url", "error.url.scheme"));
        }
        if (timeoutMs >= intervalSeconds * 1000) {
            errors.add(new play.data.validation.ValidationError(
                    "timeoutMs", "error.timeout.tooLarge"));
        }
        return errors.isEmpty() ? null : errors;
    }

    public String getServiceKey() {
        return serviceKey;
    }

    public String getName() {
        return name;
    }

    public String getUrl() {
        return url;
    }
}
