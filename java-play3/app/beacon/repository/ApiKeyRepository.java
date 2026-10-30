package beacon.repository;

import beacon.db.DatabaseExecutionContext;
import beacon.db.Rows;
import beacon.domain.ApiKey;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.Optional;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.db.Database;

@Singleton
public class ApiKeyRepository extends JdbcRepository {

    @Inject
    public ApiKeyRepository(Database db, DatabaseExecutionContext ec) {
        super(db, ec);
    }

    public CompletionStage<Optional<ApiKey>> findByPrefix(String prefix) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT id, org_id, name, key_prefix, secret_hash, created_at, last_used_at, revoked_at "
                            + "FROM api_keys WHERE key_prefix = ?")) {
                st.setString(1, prefix);
                try (ResultSet rs = st.executeQuery()) {
                    return Rows.single(rs, ApiKeyRepository::map);
                }
            }
        });
    }

    public CompletionStage<String> orgSlugOf(long apiKeyId) {
        return query(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "SELECT o.slug FROM api_keys k JOIN organizations o ON o.id = k.org_id WHERE k.id = ?")) {
                st.setLong(1, apiKeyId);
                try (ResultSet rs = st.executeQuery()) {
                    return rs.next() ? rs.getString(1) : null;
                }
            }
        });
    }

    public CompletionStage<Integer> touch(long id, Instant when) {
        return transaction(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "UPDATE api_keys SET last_used_at = ? WHERE id = ?")) {
                Rows.setInstant(st, 1, when);
                st.setLong(2, id);
                return st.executeUpdate();
            }
        });
    }

    public CompletionStage<ApiKey> create(long orgId, String name, String prefix, String secretHash) {
        return transaction(connection -> {
            try (PreparedStatement st = connection.prepareStatement(
                    "INSERT INTO api_keys (org_id, name, key_prefix, secret_hash) VALUES (?, ?, ?, ?)",
                    PreparedStatement.RETURN_GENERATED_KEYS)) {
                st.setLong(1, orgId);
                st.setString(2, name);
                st.setString(3, prefix);
                st.setString(4, secretHash);
                st.executeUpdate();
                long id = Rows.generatedKey(st);
                return new ApiKey(id, orgId, name, prefix, secretHash, Instant.now(), null, null);
            }
        });
    }

    static ApiKey map(ResultSet rs) throws SQLException {
        return new ApiKey(
                rs.getLong("id"),
                rs.getLong("org_id"),
                rs.getString("name"),
                rs.getString("key_prefix"),
                rs.getString("secret_hash"),
                Rows.instant(rs, "created_at"),
                Rows.instant(rs, "last_used_at"),
                Rows.instant(rs, "revoked_at"));
    }
}
