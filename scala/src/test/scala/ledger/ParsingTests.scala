package ledger

class ParsingTests extends munit.FunSuite:

  test("корректная строка превращается в транзакцию"):
    val result = Parsing.parseLine("t-1,food,42.50,completed", 2)
    assertEquals(
      result,
      Right(Transaction("t-1", "food", BigDecimal("42.50"), Status.Completed))
    )

  test("неверное число полей даёт ошибку"):
    assertEquals(
      Parsing.parseLine("t-1,food,42.50", 2),
      Left(ValidationError.WrongFieldCount(2, 3))
    )

  test("пустой идентификатор отклоняется"):
    assertEquals(
      Parsing.parseLine(",food,10,completed", 7),
      Left(ValidationError.EmptyId(7))
    )

  test("нечисловая сумма отклоняется"):
    assertEquals(
      Parsing.parseLine("t-1,food,abc,completed", 5),
      Left(ValidationError.InvalidAmount(5, "abc"))
    )

  test("неположительная сумма отклоняется"):
    assert(Parsing.parseLine("t-1,food,-10,completed", 3).isLeft)

  test("неизвестный статус отклоняется"):
    assertEquals(
      Parsing.parseLine("t-1,food,10,unknown", 4),
      Left(ValidationError.UnknownStatus(4, "unknown"))
    )

  test("денежная сумма не проходит через Double и сохраняет точность"):
    assertEquals(
      Parsing.parseLine("t-1,food,9007199254740993.01,completed", 2).map(_.amount),
      Right(BigDecimal("9007199254740993.01"))
    )

  test("пустая категория отклоняется"):
    assertEquals(Parsing.parseLine("t-1, ,10,completed", 2), Left(ValidationError.EmptyCategory(2)))

  test("прямой validate нормализует поля и не принимает пробельную категорию"):
    assertEquals(
      Parsing.validate(RawRecord(" t-1 ", " food ", " 10.50 ", " COMPLETED "), 2),
      Right(Transaction("t-1", "food", BigDecimal("10.50"), Status.Completed))
    )
    assertEquals(
      Parsing.validate(RawRecord("t-1", " ", "10", "completed"), 2),
      Left(ValidationError.EmptyCategory(2))
    )

  test("пустое последнее поле сохраняется и проверяется как статус"):
    assertEquals(Parsing.splitLine("t-1,food,10,"), Vector("t-1", "food", "10", ""))
    assertEquals(Parsing.parseLine("t-1,food,10,", 8), Left(ValidationError.UnknownStatus(8, "")))

  test("кавычки не поддерживаются учебным форматом"):
    assertEquals(
      Parsing.parseLine("t-1,\"food\",10,completed", 9),
      Left(ValidationError.UnsupportedQuoting(9))
    )

  test("нечисловые специальные значения не выбрасывают исключение наружу"):
    List("NaN", "Infinity", "", "not-a-number").foreach { raw =>
      assertEquals(
        Parsing.parseLine(s"t-1,food,$raw,completed", 2),
        Left(ValidationError.InvalidAmount(2, raw))
      )
    }

  test("экстремальные и выходящие за границу масштаба суммы отклоняются"):
    List("1e2147483647", "1e-2147483647", "1e129", "1e-129").foreach { raw =>
      assertEquals(
        Parsing.parseLine(s"t-1,food,$raw,completed", 2),
        Left(ValidationError.AmountOutOfRange(2))
      )
    }

  test("границы масштаба и точности принимаются без округления"):
    List("1e128", "1e-128", "9" * 128).foreach { raw =>
      assertEquals(
        Parsing.parseLine(s"t-1,food,$raw,completed", 2).map(_.amount),
        Right(BigDecimal(raw))
      )
    }
    assertEquals(
      Parsing.parseLine(s"t-1,food,${"9" * 129},completed", 2),
      Left(ValidationError.AmountOutOfRange(2))
    )

  test("слишком длинная запись отклоняется даже при небольшом значении"):
    val raw = "0" * 256 + "1"
    assertEquals(
      Parsing.parseLine(s"t-1,food,$raw,completed", 2),
      Left(ValidationError.AmountOutOfRange(2))
    )

  test("нулевая сумма отклоняется, дробная положительная сохраняется"):
    assertEquals(
      Parsing.parseLine("t-1,food,0,completed", 2),
      Left(ValidationError.NonPositiveAmount(2, BigDecimal(0)))
    )
    assertEquals(
      Parsing.parseLine("t-1,food,0.001,completed", 2).map(_.amount),
      Right(BigDecimal("0.001"))
    )

  test("статусы pending и failed распознаются, лишнее поле отвергается"):
    assertEquals(Parsing.parseLine("t-1,food,1,PENDING", 2).map(_.status), Right(Status.Pending))
    assertEquals(Parsing.parseLine("t-1,food,1,failed", 2).map(_.status), Right(Status.Failed))
    assertEquals(
      Parsing.parseLine("t-1,food,1,completed,extra", 2),
      Left(ValidationError.WrongFieldCount(2, 5))
    )
