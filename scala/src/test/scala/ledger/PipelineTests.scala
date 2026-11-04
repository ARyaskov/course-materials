package ledger

class PipelineTests extends munit.FunSuite:
  test("пустой документ и неверный заголовок — ошибки документа"):
    assertEquals(Pipeline.process(Nil), Left(DocumentError.MissingHeader))
    assertEquals(Pipeline.process(List("wrong")), Left(DocumentError.WrongHeader("wrong")))

  test("один заголовок даёт корректный пустой результат"):
    assertEquals(Pipeline.process(List(Pipeline.Header)), Right(ProcessingResult(Nil, Nil)))

  test("UTF-8 BOM допускается только перед заголовком"):
    assert(Pipeline.process(List("\uFEFF" + Pipeline.Header)).isRight)

  test("удаление пустых строк не меняет физические номера ошибок"):
    val processed = Pipeline.process(List(Pipeline.Header, "", "t-1,food,bad,completed"))
    assertEquals(processed.map(_.errors), Right(List(ValidationError.InvalidAmount(3, "bad"))))

  test("ошибки строк сохраняются отдельно от корректных транзакций"):
    val processed = Pipeline.process(
      List(
        Pipeline.Header,
        "t-1,food,10,completed",
        "t-2,food,bad,completed",
        "t-3,food,20,pending"
      )
    )
    assertEquals(processed.map(_.transactions.size), Right(2))
    assertEquals(processed.map(_.errors.size), Right(1))
    assertEquals(processed.map(_.summaries.map(_.total).sum), Right(BigDecimal(10)))

  test("все ошибочные строки дают пустую сводку с диагностикой"):
    val processed = Pipeline.process(List(Pipeline.Header, "bad", "t-1,,10,completed"))
    assertEquals(processed.map(_.transactions), Right(Nil))
    assertEquals(processed.map(_.errors.size), Right(2))

  test("повторные ID между статусами блокируют отчёт и сохраняют ошибки строк"):
    val error = ValidationError.InvalidAmount(4, "bad")
    assertEquals(
      Pipeline.process(
        List(
          Pipeline.Header,
          "t-1,food,10,completed",
          "t-1,books,20,pending",
          "t-2,food,bad,completed"
        )
      ),
      Left(DocumentError.DuplicateIds(List("t-1"), List(error)))
    )

  test("повторные ID перечислены детерминированно и без повторов"):
    val rows = List("z", "a", "z", "a", "z").map(id => s"$id,food,1,completed")
    assertEquals(
      Pipeline.process(Pipeline.Header :: rows),
      Left(DocumentError.DuplicateIds(List("a", "z"), Nil))
    )

  test("невалидная строка с тем же ID остаётся ошибкой строки"):
    val processed =
      Pipeline.process(List(Pipeline.Header, "t-1,food,1,completed", "t-1,food,bad,completed"))
    assertEquals(processed.map(_.transactions.size), Right(1))
    assertEquals(processed.map(_.errors.size), Right(1))

  test("рендеринг ошибки документа включает найденные ошибки строк"):
    val message = DocumentError.render(
      DocumentError.DuplicateIds(List("t-1"), List(ValidationError.EmptyCategory(6)))
    )
    assert(message.contains("t-1"))
    assert(message.contains("строка 6: пустая категория"))
