package beacon.db;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * Тонкий слой над JDBC: ровно то, чего не хватает при работе через {@code play.db.Database},
 * и ничего сверх того. Полноценный ORM здесь не нужен — запросы Beacon известны заранее.
 */
public final class Rows {

    @FunctionalInterface
    public interface RowMapper<T> {
        T map(ResultSet rs) throws SQLException;
    }

    private Rows() {}

    public static <T> List<T> list(ResultSet rs, RowMapper<T> mapper) throws SQLException {
        List<T> out = new ArrayList<>();
        while (rs.next()) {
            out.add(mapper.map(rs));
        }
        return out;
    }

    public static <T> Optional<T> single(ResultSet rs, RowMapper<T> mapper) throws SQLException {
        return rs.next() ? Optional.of(mapper.map(rs)) : Optional.empty();
    }

    public static Instant instant(ResultSet rs, String column) throws SQLException {
        Timestamp ts = rs.getTimestamp(column);
        return ts == null ? null : ts.toInstant();
    }

    public static LocalDate date(ResultSet rs, String column) throws SQLException {
        java.sql.Date d = rs.getDate(column);
        return d == null ? null : d.toLocalDate();
    }

    public static Integer nullableInt(ResultSet rs, String column) throws SQLException {
        int value = rs.getInt(column);
        return rs.wasNull() ? null : value;
    }

    public static void setInstant(PreparedStatement st, int index, Instant value) throws SQLException {
        if (value == null) {
            st.setNull(index, java.sql.Types.TIMESTAMP);
        } else {
            st.setTimestamp(index, Timestamp.from(value));
        }
    }

    public static long generatedKey(PreparedStatement st) throws SQLException {
        try (ResultSet keys = st.getGeneratedKeys()) {
            if (keys.next()) {
                return keys.getLong(1);
            }
            throw new SQLException("СУБД не вернула сгенерированный ключ");
        }
    }
}
