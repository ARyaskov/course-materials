package beacon.parser;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import javax.inject.Inject;
import javax.inject.Singleton;
import org.apache.pekko.stream.Materializer;
import org.apache.pekko.util.ByteString;
import play.http.HttpErrorHandler;
import play.libs.F;
import play.libs.streams.Accumulator;
import play.mvc.BodyParser;
import play.mvc.Http;
import play.mvc.Result;

/**
 * Свой {@link BodyParser}: принимает text/csv и отдаёт контроллеру уже разобранные строки.
 *
 * <p>Парсер выбирается до чтения тела, поэтому лимит в 2 МБ отсекает слишком большой файл
 * до того, как он окажется в памяти: за это отвечает {@link BodyParser.Bytes}, которому
 * мы делегируем чтение и обработку превышения (ответ 413 формирует {@link HttpErrorHandler}).
 */
@Singleton
public class CsvCheckParser implements BodyParser<CheckImport> {

    private static final long MAX_LENGTH = 2L * 1024 * 1024;
    private static final String HEADER = "service_key,name,method,url,expected_status,timeout_ms,interval_seconds";

    private final BodyParser.Bytes delegate;
    private final Materializer materializer;

    @Inject
    public CsvCheckParser(HttpErrorHandler errorHandler, Materializer materializer) {
        this.delegate = new BodyParser.Bytes(MAX_LENGTH, errorHandler);
        this.materializer = materializer;
    }

    @Override
    public Accumulator<ByteString, F.Either<Result, CheckImport>> apply(Http.RequestHeader request) {
        return delegate.apply(request).map(
                either -> either.right
                        .map(bytes -> F.Either.<Result, CheckImport>Right(parse(bytes.decodeString(StandardCharsets.UTF_8))))
                        .orElseGet(() -> F.Either.Left(either.left.orElseThrow())),
                materializer.executionContext());
    }

    public static CheckImport parse(String text) {
        List<CheckImport.Row> rows = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        String[] lines = text.split("\r?\n");
        int lineNumber = 0;
        for (String line : lines) {
            lineNumber++;
            if (line.isBlank()) {
                continue;
            }
            if (lineNumber == 1 && line.replace(" ", "").equalsIgnoreCase(HEADER)) {
                continue;
            }
            String[] cells = line.split(",", -1);
            if (cells.length < 4) {
                errors.add("строка %d: ожидается минимум 4 колонки".formatted(lineNumber));
                continue;
            }
            try {
                rows.add(new CheckImport.Row(
                        cells[0].trim(),
                        cells[1].trim(),
                        cells[2].isBlank() ? "GET" : cells[2].trim().toUpperCase(),
                        cells[3].trim(),
                        cells.length > 4 && !cells[4].isBlank() ? Integer.parseInt(cells[4].trim()) : 200,
                        cells.length > 5 && !cells[5].isBlank() ? Integer.parseInt(cells[5].trim()) : 10_000,
                        cells.length > 6 && !cells[6].isBlank() ? Integer.parseInt(cells[6].trim()) : 60));
            } catch (NumberFormatException e) {
                errors.add("строка %d: числовое поле не разобрано".formatted(lineNumber));
            }
        }
        return new CheckImport(rows, errors);
    }
}
