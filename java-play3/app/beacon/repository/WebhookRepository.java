package beacon.repository;

import beacon.db.DatabaseExecutionContext;
import beacon.db.Rows;
import beacon.domain.Webhook;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.List;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.db.Database;

@Singleton
public class WebhookRepository extends JdbcRepository {

    @Inject
    public WebhookRepository(Database db, DatabaseExecutionContext ec) {
        super(db, ec);
    }

    public CompletionStage<List<Webhook>> listEnabled(String orgSlug) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT w.id, w.org_id, w.url, w.secret, w.enabled FROM webhooks w "
                            + "JOIN organizations o ON o.id = w.org_id "
                            + "WHERE o.slug = ? AND w.enabled = TRUE")) {
                st.setString(1, orgSlug);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.list(rs, r -> new Webhook(
                            r.getLong("id"), r.getLong("org_id"),
                            r.getString("url"), r.getString("secret"), r.getBoolean("enabled")));
                }
            }
        });
    }
}
