package ledger

import java.nio.file.{Files, Path}
import scala.util.Try

/** Данные для границы процесса: тесты не вызывают sys.exit. */
final case class RunResult(exitCode: Int, stdout: String, stderr: String)

object Application:
  def execute(args: List[String]): RunResult =
    Cli.parse(args) match
      case Left(reason)                             => RunResult(2, "", reason + "\n" + Cli.Usage)
      case Right(CliRequest.Help)                   => RunResult(0, Cli.Usage, "")
      case Right(CliRequest.Process(input, output)) => executeReport(input, output)

  private def executeReport(input: String, output: Option[String]): RunResult =
    val result = for
      _ <- protectInput(input, output)
      lines <- Csv.readLines(input)
      processed <- Pipeline.process(lines).left.map(DocumentError.render)
      text = Report.render(processed.summaries)
      stdout <- output match
        case None       => Right(text)
        case Some(path) => Csv.writeReport(path, text + "\n").map(_ => s"Отчёт записан: $path")
    yield
      val diagnostics =
        if processed.errors.isEmpty then ""
        else
          (s"Пропущено записей с ошибками: ${processed.errors.size}" ::
            processed.errors.map(ValidationError.render)).mkString("\n")
      RunResult(0, stdout, diagnostics)
    result.fold(reason => RunResult(1, "", reason), identity)

  private def protectInput(input: String, output: Option[String]): Either[String, Unit] =
    output match
      case None         => Right(())
      case Some(target) =>
        Try {
          val sourcePath = Path.of(input).toAbsolutePath.normalize()
          val targetPath = Path.of(target).toAbsolutePath.normalize()
          val same = sourcePath == targetPath ||
            (Files.exists(sourcePath) && Files.exists(targetPath) &&
              Files.isSameFile(sourcePath, targetPath))
          if same then Left("входной файл и путь отчёта должны различаться") else Right(())
        }.toEither.left.map(e => s"неверный путь файла: ${e.getMessage}").flatMap(identity)
