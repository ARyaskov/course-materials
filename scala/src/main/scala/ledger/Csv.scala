package ledger

import scala.io.Source
import scala.util.{Try, Using}
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path}

/** Граница файлового ввода-вывода; текст всегда UTF-8. */
object Csv:
  def readLines(path: String): Either[String, List[String]] =
    Using(Source.fromFile(path, StandardCharsets.UTF_8.name()))(_.getLines().toList).toEither.left
      .map(e => s"не удалось прочитать файл $path: ${e.getMessage}")

  def writeReport(path: String, text: String): Either[String, Unit] =
    Try(Files.writeString(Path.of(path), text, StandardCharsets.UTF_8)).toEither
      .map(_ => ())
      .left
      .map(e => s"не удалось записать отчёт $path: ${e.getMessage}")
