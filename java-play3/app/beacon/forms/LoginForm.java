package beacon.forms;

import play.data.validation.Constraints;

public class LoginForm {

    @Constraints.Required
    @Constraints.Email
    public String email;

    @Constraints.Required
    @Constraints.MinLength(8)
    public String password;

    public String getEmail() {
        return email;
    }
}
