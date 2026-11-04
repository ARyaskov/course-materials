package ledger

/** Агрегация проверенных транзакций в сводки по категориям. */
object Aggregation:

  /** Итог по одной категории. */
  final case class CategorySummary(category: String, count: Int, total: BigDecimal)

  /** Считает статистику по категориям, учитывая только завершённые транзакции. */
  def summarize(transactions: List[Transaction]): List[CategorySummary] =
    transactions
      .filter(_.status == Status.Completed)
      .groupBy(_.category)
      .toList
      .map { (category, group) =>
        CategorySummary(category, group.size, group.map(_.amount).sum)
      }
      .sortBy(summary => (-summary.total, summary.category))
