package beacon;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import beacon.parser.CheckImport;
import beacon.parser.CsvCheckParser;
import org.junit.Test;

/** Разбор CSV — чистая функция, ей не нужен ни сервер, ни приложение. */
public class CsvCheckParserTest {

    @Test
    public void headerIsSkippedAndDefaultsApplied() {
        String csv = """
                service_key,name,method,url,expected_status,timeout_ms,interval_seconds
                api,ping,,https://example.org/ping,,,
                web,home,GET,https://example.org/,200,3000,30
                """;

        CheckImport result = CsvCheckParser.parse(csv);

        assertEquals(2, result.rows().size());
        assertEquals("GET", result.rows().get(0).method());
        assertEquals(200, result.rows().get(0).expectedStatus());
        assertEquals(10_000, result.rows().get(0).timeoutMs());
        assertEquals(30, result.rows().get(1).intervalSeconds());
        assertTrue(result.errors().isEmpty());
    }

    @Test
    public void brokenLinesAreReportedButDoNotStopImport() {
        String csv = """
                api,ok,GET,https://example.org/ok,200,1000,60
                api,broken,GET,https://example.org/x,not-a-number,1000,60
                short,line
                """;

        CheckImport result = CsvCheckParser.parse(csv);

        assertEquals(1, result.rows().size());
        assertEquals(2, result.errors().size());
    }
}
