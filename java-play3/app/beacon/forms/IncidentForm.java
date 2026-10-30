package beacon.forms;

import play.data.validation.Constraints;

public class IncidentForm {

    @Constraints.Required
    @Constraints.Pattern("[a-z0-9][a-z0-9-]{0,62}")
    public String serviceKey;

    @Constraints.Required
    @Constraints.MaxLength(300)
    public String title;

    @Constraints.Required
    @Constraints.Pattern("MINOR|MAJOR|CRITICAL")
    public String severity = "MAJOR";

    public String getTitle() {
        return title;
    }
}
