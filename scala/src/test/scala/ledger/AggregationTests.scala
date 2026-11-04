package ledger

class AggregationTests extends munit.FunSuite:

  private val txs = List(
    Transaction("1", "food", BigDecimal(10), Status.Completed),
    Transaction("2", "food", BigDecimal(15), Status.Completed),
    Transaction("3", "food", BigDecimal(99), Status.Pending), // не учитывается
    Transaction("4", "travel", BigDecimal(50), Status.Completed)
  )

  test("суммирует только завершённые транзакции по категориям"):
    val food = Aggregation.summarize(txs).find(_.category == "food").get
    assertEquals(food.count, 2)
    assertEquals(food.total, BigDecimal(25))

  test("сводки отсортированы по убыванию суммы"):
    assertEquals(
      Aggregation.summarize(txs).map(_.category),
      List("travel", "food")
    )

  test("пустой вход даёт пустой отчёт"):
    assertEquals(Aggregation.summarize(Nil), Nil)

  test("равные суммы упорядочены по названию категории"):
    val values = List(
      Transaction("a", "health", BigDecimal("10"), Status.Completed),
      Transaction("b", "books", BigDecimal("10"), Status.Completed)
    )
    assertEquals(Aggregation.summarize(values).map(_.category), List("books", "health"))
    assertEquals(Aggregation.summarize(values.reverse), Aggregation.summarize(values))

  test("failed и pending не участвуют в сводке"):
    val values = List(Status.Pending, Status.Failed).map(status =>
      Transaction(status.toString, "food", BigDecimal("100"), status)
    )
    assertEquals(Aggregation.summarize(values), Nil)

  test("десятичные суммы и счётчики сохраняются точно"):
    val values = List("0.10", "0.20").zipWithIndex.map((amount, id) =>
      Transaction(id.toString, "food", BigDecimal(amount), Status.Completed)
    )
    assertEquals(
      Aggregation.summarize(values),
      List(Aggregation.CategorySummary("food", 2, BigDecimal("0.30")))
    )
