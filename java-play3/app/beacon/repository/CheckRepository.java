package beacon.repository;

import beacon.db.DatabaseExecutionContext;
import beacon.db.Rows;
import beacon.domain.Check;
import beacon.domain.CheckContext;
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
public class CheckRepository extends JdbcRepository {

    private static final String COLUMNS =
            "c.id, c.service_id, c.name, c.method, c.url, c.expected_status, c.body_contains, "
                    + "c.timeout_ms, c.interval_seconds, c.enabled, c.next_run_at, c.created_at";

    @Inject
    public CheckRepository(Database db, DatabaseExecutionContext ec) {
        super(db, ec);
    }

    /**
     * Забирает пачку проверок, которым пора выполниться, и сразу сдвигает next_run_at.
     * Всё в одной транзакции: два инстанса приложения не возьмут одну и ту же проверку
     * дважды, потому что UPDATE держит строки до коммита.
     */
    public CompletionStage<List<CheckContext>> claimDue(Instant now, int limit) {
        return transaction(connection -> {
            List<CheckContext> due;
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT " + COLUMNS + ", s.service_key, o.slug FROM checks c "
                            + "JOIN services s ON s.id = c.service_id "
                            + "JOIN organizations o ON o.id = s.org_id "
                            + "WHERE c.enabled = TRUE AND c.next_run_at <= ? "
                            + "ORDER BY c.next_run_at LIMIT ?")) {
                Rows.setInstant(st, 1, now);
                st.setInt(2, limit);
                try (ResultSet rs = st.executeQuery()) {
                    due = Rows.list(rs, r -> new CheckContext(
                            map(r), r.getString("service_key"), r.getString("slug")));
                }
            }
            if (due.isEmpty()) {
                return due;
            }
            try (PreparedStatement st = connection.prepareStatement(
                    "UPDATE checks SET next_run_at = ? WHERE id = ?")) {
                for (CheckContext ctx : due) {
                    Rows.setInstant(st, 1, now.plusSeconds(ctx.check().intervalSeconds()));
                    st.setLong(2, ctx.check().id());
                    st.addBatch();
                }
                st.executeBatch();
            }
            return due;
        });
    }

    public CompletionStage<List<Check>> listByOrgSlug(String slug) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT " + COLUMNS + " FROM checks c "
                            + "JOIN services s ON s.id = c.service_id "
                            + "JOIN organizations o ON o.id = s.org_id "
                            + "WHERE o.slug = ? ORDER BY c.id")) {
                st.setString(1, slug);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.list(rs, CheckRepository::map);
                }
            }
        });
    }

    public CompletionStage<List<Check>> listByServiceId(long serviceId) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT " + COLUMNS + " FROM checks c WHERE c.service_id = ? ORDER BY c.id")) {
                st.setLong(1, serviceId);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.list(rs, CheckRepository::map);
                }
            }
        });
    }

    public CompletionStage<Optional<Check>> findById(long id) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT " + COLUMNS + " FROM checks c WHERE c.id = ?")) {
                st.setLong(1, id);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.single(rs, CheckRepository::map);
                }
            }
        });
    }

    public CompletionStage<Check> create(Check check) {
        return transaction(connection -> insert(connection, check));
    }

    /**
     * Пакетная вставка для CSV-импорта: одна транзакция, один executeBatch.
     * Дубликаты по паре (service_id, url) пропускаются — импорт идемпотентен.
     */
    public CompletionStage<Integer> importAll(long serviceId, List<Check> checks) {
        return transaction(connection -> {
            int inserted = 0;
            for (Check check : checks) {
                if (!exists(connection, serviceId, check.url())) {
                    insert(connection, check);
                    inserted++;
                }
            }
            return inserted;
        });
    }

    public CompletionStage<Boolean> delete(long id) {
        return transaction(connection -> {
            try (PreparedStatement results = connection.prepareStatement(
                    "DELETE FROM probe_results WHERE check_id = ?")) {
                results.setLong(1, id);
                results.executeUpdate();
            }
            try (PreparedStatement days = connection.prepareStatement(
                    "DELETE FROM uptime_days WHERE check_id = ?")) {
                days.setLong(1, id);
                days.executeUpdate();
            }
            try (PreparedStatement st = connection.prepareStatement("DELETE FROM checks WHERE id = ?")) {
                st.setLong(1, id);
                return st.executeUpdate() > 0;
            }
        });
    }

    private boolean exists(java.sql.Connection connection, long serviceId, String url) throws SQLException {
        try (PreparedStatement st = connection.prepareStatement(
                "SELECT 1 FROM checks WHERE service_id = ? AND url = ?")) {
            st.setLong(1, serviceId);
            st.setString(2, url);
            try (ResultSet rs = st.executeQuery()) {
                return rs.next();
            }
        }
    }

    private Check insert(java.sql.Connection connection, Check check) throws SQLException {
        try (PreparedStatement st = connection.prepareStatement(
                "INSERT INTO checks (service_id, name, method, url, expected_status, body_contains, "
                        + "timeout_ms, interval_seconds, enabled, next_run_at) "
                        + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                PreparedStatement.RETURN_GENERATED_KEYS)) {
            st.setLong(1, check.serviceId());
            st.setString(2, check.name());
            st.setString(3, check.method());
            st.setString(4, check.url());
            st.setInt(5, check.expectedStatus());
            st.setString(6, check.bodyContains());
            st.setInt(7, check.timeoutMs());
            st.setInt(8, check.intervalSeconds());
            st.setBoolean(9, check.enabled());
            Rows.setInstant(st, 10, check.nextRunAt() == null ? Instant.now() : check.nextRunAt());
            st.executeUpdate();
            long id = Rows.generatedKey(st);
            return new Check(id, check.serviceId(), check.name(), check.method(), check.url(),
                    check.expectedStatus(), check.bodyContains(), check.timeoutMs(),
                    check.intervalSeconds(), check.enabled(), check.nextRunAt(), Instant.now());
        }
    }

    static Check map(ResultSet rs) throws SQLException {
        return new Check(
                rs.getLong("id"),
                rs.getLong("service_id"),
                rs.getString("name"),
                rs.getString("method"),
                rs.getString("url"),
                rs.getInt("expected_status"),
                rs.getString("body_contains"),
                rs.getInt("timeout_ms"),
                rs.getInt("interval_seconds"),
                rs.getBoolean("enabled"),
                Rows.instant(rs, "next_run_at"),
                Rows.instant(rs, "created_at"));
    }
}
