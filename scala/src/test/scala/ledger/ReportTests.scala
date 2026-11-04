package ledger

class ReportTests extends munit.FunSuite:
  test("пустой отчёт имеет понятное сообщение"):
    assertEquals(Report.render(Nil), "Нет завершённых транзакций для отчёта.")

  test("в отчёте есть заголовок и точная общая сумма"):
    val text = Report.render(
      List(
        Aggregation.CategorySummary("food", 2, BigDecimal("0.30")),
        Aggregation.CategorySummary("books", 1, BigDecimal("50"))
      )
    )
    assert(text.startsWith("Категория"))
    assert(text.linesIterator.toList.last.contains("50.30"))
    assert(text.linesIterator.toList.last.contains("3"))

  test("дополнительные десятичные знаки не округляются скрыто"):
    val text = Report.render(List(Aggregation.CategorySummary("food", 1, BigDecimal("0.001"))))
    assert(text.contains("0.001"))

  test("крупное значение печатается без научной записи"):
    val text = Report.render(List(Aggregation.CategorySummary("food", 1, BigDecimal("1E+8"))))
    assert(text.contains("100000000.00"))
