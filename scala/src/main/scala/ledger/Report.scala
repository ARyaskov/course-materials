package ledger

/** Формирование текстового отчёта по сводкам категорий. */
object Report:

  private def money(v: BigDecimal): String =
    v.setScale(math.max(2, v.scale)).bigDecimal.toPlainString

  /** Собирает выровненный по колонкам текстовый отчёт. */
  def render(summaries: List[Aggregation.CategorySummary]): String =
    if summaries.isEmpty then "Нет завершённых транзакций для отчёта."
    else
      val header = f"${"Категория"}%-15s ${"Кол-во"}%6s ${"Сумма"}%12s"
      val rows = summaries.map { s =>
        f"${s.category}%-15s ${s.count}%6d ${money(s.total)}%12s"
      }
      val totalCount = summaries.map(_.count).sum
      val totalSum = money(summaries.map(_.total).sum)
      val footer = f"${"ИТОГО"}%-15s ${totalCount}%6d ${totalSum}%12s"
      (header +: rows :+ footer).mkString("\n")
