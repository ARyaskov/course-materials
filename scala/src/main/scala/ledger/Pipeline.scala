package ledger

/** Все корректные записи сохраняются, даже если их статус не Completed. */
final case class ProcessingResult(
    transactions: List[Transaction],
    errors: List[ValidationError]
):
  def summaries: List[Aggregation.CategorySummary] = Aggregation.summarize(transactions)

/** Чистая обработка документа: без чтения файлов, печати и изменения состояния. */
object Pipeline:
  val Header: String = "id,category,amount,status"

  def process(lines: List[String]): Either[DocumentError, ProcessingResult] =
    lines match
      case Nil => Left(DocumentError.MissingHeader)
      case header :: _ if header.stripPrefix("\uFEFF") != Header =>
        Left(DocumentError.WrongHeader(header))
      case _ =>
        val parsed = lines.zipWithIndex
          .drop(1)
          .filter((line, _) => line.trim.nonEmpty)
          .map((line, index) => Parsing.parseLine(line, index + 1))
        val errors = parsed.collect { case Left(error) => error }
        val transactions = parsed.collect { case Right(transaction) => transaction }
        val duplicates = transactions
          .groupBy(_.id)
          .toList
          .filter((_, group) => group.size > 1)
          .map(_._1)
          .sorted
        if duplicates.nonEmpty then Left(DocumentError.DuplicateIds(duplicates, errors))
        else Right(ProcessingResult(transactions, errors))
