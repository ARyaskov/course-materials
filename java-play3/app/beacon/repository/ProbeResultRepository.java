package beacon.repository;

import beacon.db.DatabaseExecutionContext;
import beacon.db.Rows;
import beacon.domain.ProbeOutcome;
import beacon.domain.ProbeResult;
import beacon.domain.UptimeDay;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.db.Database;

@Singleton
public class ProbeResultRepository extends JdbcRepository {

    @Inject
    public ProbeResultRepository(Database db, DatabaseExecutionContext ec) {
        super(db, ec);
    }

    /** Записывает результат пробы и тут же обновляет дневной агрегат — одной транзакцией. */
    public CompletionStage<ProbeResult> save(ProbeResult result) {
        return transaction(connection -> {
            long id;
            try (PreparedStatement st = connection.prepareStatement(
                    "INSERT INTO probe_results (check_id, started_at, duration_ms, status_code, outcome, error) "
                            + "VALUES (?, ?, ?, ?, ?, ?)",
                    PreparedStatement.RETURN_GENERATED_KEYS)) {
                st.setLong(1, result.checkId());
                Rows.setInstant(st, 2, result.startedAt());
                st.setLong(3, result.durationMs());
                if (result.statusCode() == null) {
                    st.setNull(4, java.sql.Types.INTEGER);
                } else {
                    st.setInt(4, result.statusCode());
                }
                st.setString(5, result.outcome().name());
                st.setString(6, result.error());
                st.executeUpdate();
                id = Rows.generatedKey(st);
            }
            rollup(connection, result);
            return new ProbeResult(id, result.checkId(), result.startedAt(), result.durationMs(),
                    result.statusCode(), result.outcome(), result.error());
        });
    }

    /**
     * Дневной агрегат: сначала UPDATE, если строки нет — INSERT.
     * Написано переносимо; на PostgreSQL то же самое делается одним
     * INSERT ... ON CONFLICT (check_id, day_utc) DO UPDATE.
     */
    private void rollup(Connection connection, ProbeResult result) throws SQLException {
        LocalDate day = result.startedAt().atZone(ZoneOffset.UTC).toLocalDate();
        int up = result.outcome() == ProbeOutcome.DOWN ? 0 : 1;
        try (PreparedStatement st = connection.prepareStatement(
                "UPDATE uptime_days SET up_count = up_count + ?, total_count = total_count + 1, "
                        + "avg_duration_ms = (avg_duration_ms * total_count + ?) / (total_count + 1) "
                        + "WHERE check_id = ? AND day_utc = ?")) {
            st.setInt(1, up);
            st.setLong(2, result.durationMs());
            st.setLong(3, result.checkId());
            st.setObject(4, day);
            if (st.executeUpdate() > 0) {
                return;
            }
        }
        try (PreparedStatement st = connection.prepareStatement(
                "INSERT INTO uptime_days (check_id, day_utc, up_count, total_count, avg_duration_ms) "
                        + "VALUES (?, ?, ?, 1, ?)")) {
            st.setLong(1, result.checkId());
            st.setObject(2, day);
            st.setInt(3, up);
            st.setLong(4, result.durationMs());
            st.executeUpdate();
        }
    }

    /** Последние N исходов проверки — по ним детектор решает, открывать ли инцидент. */
    public CompletionStage<List<ProbeOutcome>> recentOutcomes(long checkId, int limit) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT outcome FROM probe_results WHERE check_id = ? ORDER BY started_at DESC LIMIT ?")) {
                st.setLong(1, checkId);
                st.setInt(2, limit);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.list(rs, r -> ProbeOutcome.valueOf(r.getString("outcome")));
                }
            }
        });
    }

    public CompletionStage<List<ProbeResult>> listByCheck(long checkId, Instant from, int limit) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT id, check_id, started_at, duration_ms, status_code, outcome, error "
                            + "FROM probe_results WHERE check_id = ? AND started_at >= ? "
                            + "ORDER BY started_at DESC LIMIT ?")) {
                st.setLong(1, checkId);
                Rows.setInstant(st, 2, from);
                st.setInt(3, limit);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.list(rs, ProbeResultRepository::map);
                }
            }
        });
    }

    /**
     * p95 без оконных функций и без расширений: считаем количество строк и берём
     * нужную по счёту через LIMIT/OFFSET. Работает и на PostgreSQL, и на H2.
     */
    public CompletionStage<Long> p95Duration(long checkId, Instant from) {
        return query(connection -> {
            int total;
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT COUNT(*) FROM probe_results WHERE check_id = ? AND started_at >= ?")) {
                st.setLong(1, checkId);
                Rows.setInstant(st, 2, from);
                try (ResultSet rs = st.executeQuery()) {
                    rs.next();
                    total = rs.getInt(1);
                }
            }
            if (total == 0) {
                return 0L;
            }
            int offset = (int) Math.floor(total * 0.95);
            if (offset >= total) {
                offset = total - 1;
            }
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT duration_ms FROM probe_results WHERE check_id = ? AND started_at >= ? "
                            + "ORDER BY duration_ms LIMIT 1 OFFSET ?")) {
                st.setLong(1, checkId);
                Rows.setInstant(st, 2, from);
                st.setInt(3, offset);
                try (ResultSet rs = st.executeQuery()) {
                    return rs.next() ? rs.getLong(1) : 0L;
                }
            }
        });
    }

    public CompletionStage<List<UptimeDay>> history(long checkId, int days) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT check_id, day_utc, up_count, total_count, avg_duration_ms FROM uptime_days "
                            + "WHERE check_id = ? AND day_utc >= ? ORDER BY day_utc")) {
                st.setLong(1, checkId);
                st.setObject(2, LocalDate.now(ZoneOffset.UTC).minusDays(days));
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.list(rs, r -> new UptimeDay(
                            r.getLong("check_id"),
                            Rows.date(r, "day_utc"),
                            r.getInt("up_count"),
                            r.getInt("total_count"),
                            r.getLong("avg_duration_ms")));
                }
            }
        });
    }

    static ProbeResult map(ResultSet rs) throws SQLException {
        return new ProbeResult(
                rs.getLong("id"),
                rs.getLong("check_id"),
                Rows.instant(rs, "started_at"),
                rs.getLong("duration_ms"),
                Rows.nullableInt(rs, "status_code"),
                ProbeOutcome.valueOf(rs.getString("outcome")),
                rs.getString("error"));
    }
}
