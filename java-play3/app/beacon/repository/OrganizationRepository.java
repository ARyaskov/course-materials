package beacon.repository;

import beacon.db.DatabaseExecutionContext;
import beacon.db.Rows;
import beacon.domain.Organization;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Optional;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.db.Database;

@Singleton
public class OrganizationRepository extends JdbcRepository {

    public record AdminUser(long id, long orgId, String email, String passwordHash) {}

    @Inject
    public OrganizationRepository(Database db, DatabaseExecutionContext ec) {
        super(db, ec);
    }

    public CompletionStage<Optional<Organization>> findBySlug(String slug) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT id, slug, name, created_at FROM organizations WHERE slug = ?")) {
                st.setString(1, slug);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.single(rs, this::mapOrganization);
                }
            }
        });
    }

    public CompletionStage<Optional<AdminUser>> findAdminByEmail(String email) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT id, org_id, email, password_hash FROM admin_users WHERE email = ?")) {
                st.setString(1, email);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.single(rs, r -> new AdminUser(
                            r.getLong("id"), r.getLong("org_id"),
                            r.getString("email"), r.getString("password_hash")));
                }
            }
        });
    }

    public CompletionStage<Organization> create(String slug, String name) {
        return transaction(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "INSERT INTO organizations (slug, name) VALUES (?, ?)",
                    PreparedStatement.RETURN_GENERATED_KEYS)) {
                st.setString(1, slug);
                st.setString(2, name);
                st.executeUpdate();
                long id = Rows.generatedKey(st);
                return new Organization(id, slug, name, java.time.Instant.now());
            }
        });
    }

    public CompletionStage<java.util.List<Organization>> listAll() {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT id, slug, name, created_at FROM organizations ORDER BY name")) {
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.list(rs, this::mapOrganization);
                }
            }
        });
    }

    private Organization mapOrganization(ResultSet rs) throws java.sql.SQLException {
        return new Organization(
                rs.getLong("id"),
                rs.getString("slug"),
                rs.getString("name"),
                Rows.instant(rs, "created_at"));
    }
}
