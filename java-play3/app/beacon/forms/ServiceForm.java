package beacon.forms;

import play.data.validation.Constraints;

public class ServiceForm {

    @Constraints.Required
    @Constraints.Pattern("[a-z0-9][a-z0-9-]{0,62}")
    public String key;

    @Constraints.Required
    @Constraints.MaxLength(200)
    public String name;

    @Constraints.MaxLength(1000)
    public String description;

    public int position = 0;

    public String getKey() {
        return key;
    }

    public String getName() {
        return name;
    }
}
