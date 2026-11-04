package ledger

/** Сырая строка из CSV: поля уже разделены, но ещё не проверены. */
final case class RawRecord(
    id: String,
    category: String,
    amount: String,
    status: String
)

/** Проверенная доменная модель транзакции. */
final case class Transaction(
    id: String,
    category: String,
    amount: BigDecimal,
    status: Status
)

/** Статус транзакции — фиксированный набор вариантов. */
enum Status:
  case Completed, Pending, Failed

object Status:
  /** Разбирает статус из строки без учёта регистра. */
  def parse(raw: String): Option[Status] =
    raw.trim.toLowerCase(java.util.Locale.ROOT) match
      case "completed" => Some(Status.Completed)
      case "pending"   => Some(Status.Pending)
      case "failed"    => Some(Status.Failed)
      case _           => None
