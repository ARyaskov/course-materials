package beacon.repository;

import beacon.db.DatabaseExecutionContext;
import beacon.db.Rows;
import beacon.domain.MonitoredService;
import beacon.domain.ServiceKey;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.db.Database;

@Singleton
public class ServiceRepository extends JdbcRepository {

    private static final String COLUMNS =
            "s.id, s.org_id, s.service_key, s.name, s.description, s.position, s.created_at";

    @Inject
    public ServiceRepository(Database db, DatabaseExecutionContext ec) {
        super(db, ec);
    }

    public CompletionStage<List<MonitoredService>> listByOrgSlug(String slug) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT " + COLUMNS + " FROM services s "
                            + "JOIN organizations o ON o.id = s.org_id "
                            + "WHERE o.slug = ? ORDER BY s.position, s.id")) {
                st.setString(1, slug);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.list(rs, ServiceRepository::map);
                }
            }
        });
    }

    public CompletionStage<Optional<MonitoredService>> findByKey(String orgSlug, ServiceKey key) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT " + COLUMNS + " FROM services s "
                            + "JOIN organizations o ON o.id = s.org_id "
                            + "WHERE o.slug = ? AND s.service_key = ?")) {
                st.setString(1, orgSlug);
                st.setString(2, key.value());
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.single(rs, ServiceRepository::map);
                }
            }
        });
    }

    public CompletionStage<MonitoredService> create(long orgId, ServiceKey key, String name, String description, int position) {
        return transaction(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "INSERT INTO services (org_id, service_key, name, description, position) VALUES (?, ?, ?, ?, ?)",
                    PreparedStatement.RETURN_GENERATED_KEYS)) {
                st.setLong(1, orgId);
                st.setString(2, key.value());
                st.setString(3, name);
                st.setString(4, description);
                st.setInt(5, position);
                st.executeUpdate();
                long id = Rows.generatedKey(st);
                return new MonitoredService(id, orgId, key, name, description, position, java.time.Instant.now());
            }
        });
    }

    static MonitoredService map(ResultSet rs) throws SQLException {
        return new MonitoredService(
                rs.getLong("id"),
                rs.getLong("org_id"),
                ServiceKey.of(rs.getString("service_key")),
                rs.getString("name"),
                rs.getString("description"),
                rs.getInt("position"),
                Rows.instant(rs, "created_at"));
    }
}
