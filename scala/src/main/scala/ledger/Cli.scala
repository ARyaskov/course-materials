package ledger

enum CliRequest:
  case Help
  case Process(input: String, output: Option[String])

object Cli:
  val Usage: String = "Использование: ledger <вход.csv> [--output <отчёт.txt>]\nledger --help"

  def parse(args: List[String]): Either[String, CliRequest] = args match
    case List("--help" | "-h")                                    => Right(CliRequest.Help)
    case List(input) if input.nonEmpty && !input.startsWith("--") =>
      Right(CliRequest.Process(input, None))
    case List(input, "--output", output)
        if input.nonEmpty && !input.startsWith("--") && output.nonEmpty =>
      Right(CliRequest.Process(input, Some(output)))
    case _ => Left("неверные аргументы запуска")
