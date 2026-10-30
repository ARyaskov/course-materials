package beacon.repository;

import beacon.db.DatabaseExecutionContext;
import beacon.db.Rows;
import beacon.domain.Incident;
import beacon.domain.IncidentSeverity;
import beacon.domain.IncidentUpdate;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.db.Database;

@Singleton
public class IncidentRepository extends JdbcRepository {

    private static final String COLUMNS =
            "i.id, i.service_id, i.title, i.severity, i.opened_at, i.resolved_at, i.auto_created";

    @Inject
    public IncidentRepository(Database db, DatabaseExecutionContext ec) {
        super(db, ec);
    }

    public CompletionStage<Optional<Incident>> findOpenByService(long serviceId) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT " + COLUMNS + " FROM incidents i "
                            + "WHERE i.service_id = ? AND i.resolved_at IS NULL ORDER BY i.opened_at DESC LIMIT 1")) {
                st.setLong(1, serviceId);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.single(rs, IncidentRepository::map);
                }
            }
        });
    }

    public CompletionStage<List<Incident>> listByOrgSlug(String slug, boolean onlyOpen, int limit, int offset) {
        return query(connection -> {
            String filter = onlyOpen ? " AND i.resolved_at IS NULL" : "";
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT " + COLUMNS + " FROM incidents i "
                            + "JOIN services s ON s.id = i.service_id "
                            + "JOIN organizations o ON o.id = s.org_id "
                            + "WHERE o.slug = ?" + filter
                            + " ORDER BY i.opened_at DESC LIMIT ? OFFSET ?")) {
                st.setString(1, slug);
                st.setInt(2, limit);
                st.setInt(3, offset);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.list(rs, IncidentRepository::map);
                }
            }
        });
    }

    public CompletionStage<List<Incident>> listOpenByOrgSlug(String slug) {
        return listByOrgSlug(slug, true, 100, 0);
    }

    /**
     * Открывает инцидент, если по сервису ещё нет открытого. Проверка и вставка
     * в одной транзакции, поэтому две параллельные пробы не создадут два инцидента.
     */
    public CompletionStage<Optional<Incident>> openIfAbsent(
            long serviceId, String title, IncidentSeverity severity, boolean autoCreated) {
        return transaction(connection -> {
            try (PreparedStatement existing = connection.prepareStatement(
                    "SELECT " + COLUMNS + " FROM incidents i "
                            + "WHERE i.service_id = ? AND i.resolved_at IS NULL LIMIT 1")) {
                existing.setLong(1, serviceId);
                try (ResultSet rs = existing.executeQuery()) {
                    if (rs.next()) {
                        return Optional.<Incident>empty();
                    }
                }
            }
            Instant now = Instant.now();
            try (PreparedStatement st = connection.prepareStatement(
                    "INSERT INTO incidents (service_id, title, severity, opened_at, auto_created) "
                            + "VALUES (?, ?, ?, ?, ?)",
                    PreparedStatement.RETURN_GENERATED_KEYS)) {
                st.setLong(1, serviceId);
                st.setString(2, title);
                st.setString(3, severity.name());
                Rows.setInstant(st, 4, now);
                st.setBoolean(5, autoCreated);
                st.executeUpdate();
                long id = Rows.generatedKey(st);
                addUpdate(connection, id, "investigating", "Инцидент открыт автоматически по серии неудачных проб.");
                return Optional.of(new Incident(id, serviceId, title, severity, now, null, autoCreated));
            }
        });
    }

    public CompletionStage<Optional<Incident>> resolve(long incidentId, String comment) {
        return transaction(connection -> {
            Instant now = Instant.now();
            try (PreparedStatement st = connection.prepareStatement(
                    "UPDATE incidents SET resolved_at = ? WHERE id = ? AND resolved_at IS NULL")) {
                Rows.setInstant(st, 1, now);
                st.setLong(2, incidentId);
                if (st.executeUpdate() == 0) {
                    return Optional.<Incident>empty();
                }
            }
            addUpdate(connection, incidentId, "resolved", comment);
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT " + COLUMNS + " FROM incidents i WHERE i.id = ?")) {
                st.setLong(1, incidentId);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.single(rs, IncidentRepository::map);
                }
            }
        });
    }

    public CompletionStage<List<IncidentUpdate>> updates(long incidentId) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT id, incident_id, created_at, status, body FROM incident_updates "
                            + "WHERE incident_id = ? ORDER BY created_at")) {
                st.setLong(1, incidentId);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.list(rs, r -> new IncidentUpdate(
                            r.getLong("id"), r.getLong("incident_id"),
                            Rows.instant(r, "created_at"), r.getString("status"), r.getString("body")));
                }
            }
        });
    }

    private void addUpdate(java.sql.Connection connection, long incidentId, String status, String body)
            throws SQLException {
        try (PreparedStatement st = connection.prepareStatement(
                "INSERT INTO incident_updates (incident_id, status, body) VALUES (?, ?, ?)")) {
            st.setLong(1, incidentId);
            st.setString(2, status);
            st.setString(3, body);
            st.executeUpdate();
        }
    }

    static Incident map(ResultSet rs) throws SQLException {
        return new Incident(
                rs.getLong("id"),
                rs.getLong("service_id"),
                rs.getString("title"),
                IncidentSeverity.valueOf(rs.getString("severity")),
                Rows.instant(rs, "opened_at"),
                Rows.instant(rs, "resolved_at"),
                rs.getBoolean("auto_created"));
    }
}
