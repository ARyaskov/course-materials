package ledger

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path}

class ApplicationTests extends munit.FunSuite:
  private def withFiles(content: String)(check: (Path, Path) => Unit): Unit =
    val directory = Files.createTempDirectory("ledger-test-")
    val input = directory.resolve("input.csv")
    val output = directory.resolve("report.txt")
    try
      Files.writeString(input, content, StandardCharsets.UTF_8)
      check(input, output)
    finally
      Files.deleteIfExists(output)
      Files.deleteIfExists(input)
      Files.deleteIfExists(directory)

  test("help и ошибка аргументов имеют разные коды и потоки"):
    val help = Application.execute(List("--help"))
    assertEquals(help.exitCode, 0)
    assert(help.stdout.contains("Использование"))
    assertEquals(help.stderr, "")
    val wrong = Application.execute(Nil)
    assertEquals(wrong.exitCode, 2)
    assertEquals(wrong.stdout, "")
    assert(wrong.stderr.contains("Использование"))

  test("лишние и пустые аргументы не принимаются"):
    List(
      List(""),
      List("--unknown"),
      List("in.csv", "--output"),
      List("in.csv", "--output", ""),
      List("a", "b")
    ).foreach { args =>
      assertEquals(Application.execute(args).exitCode, 2)
    }

  test("нет входного файла — ошибка без отчёта"):
    withFiles(Pipeline.Header) { (input, _) =>
      Files.delete(input)
      val result = Application.execute(List(input.toString))
      assertEquals(result.exitCode, 1)
      assertEquals(result.stdout, "")
      assert(result.stderr.contains("не удалось прочитать файл"))
    }

  test("повреждённый заголовок не перезаписывает существующий отчёт"):
    withFiles("wrong\nt-1,food,10,completed") { (input, output) =>
      Files.writeString(output, "keep")
      val result = Application.execute(List(input.toString, "--output", output.toString))
      assertEquals(result.exitCode, 1)
      assertEquals(Files.readString(output), "keep")
    }

  test("отчёт записывается в UTF-8, диагностика остаётся в stderr"):
    withFiles(Pipeline.Header + "\nt-1,продукты,10.50,completed\nt-2,food,bad,completed") {
      (input, output) =>
        val result = Application.execute(List(input.toString, "--output", output.toString))
        assertEquals(result.exitCode, 0)
        val text = Files.readString(output, StandardCharsets.UTF_8)
        assert(text.contains("продукты"))
        assert(text.contains("10.50"))
        assert(!text.contains("не является числом"))
        assert(result.stderr.contains("строка 3"))
    }

  test("путь отчёта не может совпадать с входным файлом"):
    val content = Pipeline.Header + "\nt-1,food,10,completed"
    withFiles(content) { (input, _) =>
      val result = Application.execute(List(input.toString, "--output", input.toString))
      assertEquals(result.exitCode, 1)
      assertEquals(Files.readString(input), content)
    }

  test("ошибка записи не выдаётся за успешный отчёт"):
    withFiles(Pipeline.Header + "\nt-1,food,10,completed") { (input, output) =>
      val missing = output.resolve("missing/report.txt")
      val result = Application.execute(List(input.toString, "--output", missing.toString))
      assertEquals(result.exitCode, 1)
      assert(result.stderr.contains("не удалось записать"))
      assertEquals(result.stdout, "")
    }

  test("дубли блокируют сводку, сохраняя обнаруженные ошибки строк"):
    withFiles(Pipeline.Header + "\nt-1,food,10,completed\nt-1,food,20,pending\nbad") { (input, _) =>
      val result = Application.execute(List(input.toString))
      assertEquals(result.exitCode, 1)
      assertEquals(result.stdout, "")
      assert(result.stderr.contains("повторные идентификаторы t-1"))
      assert(result.stderr.contains("строка 4"))
    }

  test("ошибки строк не останавливают обработку остальных записей"):
    withFiles(Pipeline.Header + "\nt-1,food,10,completed\nt-2,food,bad,completed") { (input, _) =>
      val result = Application.execute(List(input.toString))
      assertEquals(result.exitCode, 0)
      assert(result.stdout.contains("10.00"))
      assert(result.stderr.contains("Пропущено записей с ошибками: 1"))
    }

  test("один заголовок является допустимым пустым набором данных"):
    withFiles(Pipeline.Header) { (input, _) =>
      val result = Application.execute(List(input.toString))
      assertEquals(result.exitCode, 0)
      assertEquals(result.stdout, "Нет завершённых транзакций для отчёта.")
      assertEquals(result.stderr, "")
    }

  test("экстремальная экспонента становится диагностикой, остальные строки дают отчёт"):
    withFiles(
      Pipeline.Header +
        "\nt-1,food,1e2147483647,completed\nt-2,food,1e-2147483647,completed" +
        "\nt-3,food,10.50,completed"
    ) { (input, output) =>
      val result = Application.execute(List(input.toString, "--output", output.toString))
      assertEquals(result.exitCode, 0)
      assertEquals(result.stdout, s"Отчёт записан: $output")
      assert(Files.readString(output).contains("10.50"))
      assert(result.stderr.contains("Пропущено записей с ошибками: 2"))
      assert(result.stderr.contains(ValidationError.render(ValidationError.AmountOutOfRange(2))))
      assert(result.stderr.contains(ValidationError.render(ValidationError.AmountOutOfRange(3))))
    }
