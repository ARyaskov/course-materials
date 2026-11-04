package ledger

/** Ошибка проверки одной записи. Хранит номер строки для понятных сообщений. */
enum ValidationError:
  case WrongFieldCount(line: Int, found: Int)
  case EmptyId(line: Int)
  case EmptyCategory(line: Int)
  case UnsupportedQuoting(line: Int)
  case InvalidAmount(line: Int, raw: String)
  case AmountOutOfRange(line: Int)
  case NonPositiveAmount(line: Int, value: BigDecimal)
  case UnknownStatus(line: Int, raw: String)

object ValidationError:
  /** Человекочитаемое сообщение об ошибке для вывода в консоль. */
  def render(e: ValidationError): String = e match
    case WrongFieldCount(line, found) =>
      s"строка $line: ожидалось 4 поля, найдено $found"
    case EmptyId(line) =>
      s"строка $line: пустой идентификатор"
    case EmptyCategory(line) =>
      s"строка $line: пустая категория"
    case UnsupportedQuoting(line) =>
      s"строка $line: кавычки не поддерживаются учебным CSV-форматом"
    case InvalidAmount(line, raw) =>
      s"строка $line: сумма не является числом ($raw)"
    case AmountOutOfRange(line) =>
      s"строка $line: сумма превышает допустимую длину, точность или масштаб"
    case NonPositiveAmount(line, value) =>
      s"строка $line: сумма должна быть положительной ($value)"
    case UnknownStatus(line, raw) =>
      s"строка $line: неизвестный статус ($raw)"

/** Ошибка документа целиком: отчёт в этих случаях не строится. */
enum DocumentError:
  case MissingHeader
  case WrongHeader(actual: String)
  case DuplicateIds(ids: List[String], rowErrors: List[ValidationError])

object DocumentError:
  def render(error: DocumentError): String = error match
    case DocumentError.MissingHeader       => "файл пуст: отсутствует заголовок"
    case DocumentError.WrongHeader(actual) =>
      s"ожидался заголовок id,category,amount,status; получено: $actual"
    case DocumentError.DuplicateIds(ids, rowErrors) =>
      val message = s"отчёт не построен: повторные идентификаторы ${ids.mkString(", ")}"
      (message :: rowErrors.map(ValidationError.render)).mkString("\n")
