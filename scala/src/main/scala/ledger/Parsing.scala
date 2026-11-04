package ledger

import scala.util.Try

/** Разбор и проверка входных строк CSV. */
object Parsing:

  // Ограничиваем и исходный текст, и масштаб: короткая экспонента может
  // потребовать миллиарды цифр при форматировании в обычную десятичную запись.
  private val MaxAmountLength = 256
  private val MaxAmountPrecision = 128
  private val MaxAmountScale = 128

  /** Делит строку на поля по запятой, сохраняя пустые поля и подрезая пробелы. */
  def splitLine(line: String): Vector[String] =
    line.split(",", -1).toVector.map(_.trim)

  /** Проверяет сырую запись и строит доменную модель либо возвращает ошибку. */
  def validate(raw: RawRecord, line: Int): Either[ValidationError, Transaction] =
    for
      _ <- Either.cond(raw.id.trim.nonEmpty, (), ValidationError.EmptyId(line))
      _ <- Either.cond(raw.category.trim.nonEmpty, (), ValidationError.EmptyCategory(line))
      amount <- parseAmount(raw.amount, line)
      _ <- Either.cond(amount > BigDecimal(0), (), ValidationError.NonPositiveAmount(line, amount))
      status <- Status
        .parse(raw.status)
        .toRight(ValidationError.UnknownStatus(line, raw.status))
    yield Transaction(raw.id.trim, raw.category.trim, amount, status)

  private def parseAmount(raw: String, line: Int): Either[ValidationError, BigDecimal] =
    val text = raw.trim
    if text.length > MaxAmountLength then Left(ValidationError.AmountOutOfRange(line))
    else
      Try(BigDecimal(text)).toEither.left
        .map(_ => ValidationError.InvalidAmount(line, raw))
        .flatMap { amount =>
          Either.cond(
            amount.precision <= MaxAmountPrecision &&
              amount.scale >= -MaxAmountScale && amount.scale <= MaxAmountScale,
            amount,
            ValidationError.AmountOutOfRange(line)
          )
        }

  /** Разбирает одну строку файла (с её номером) в транзакцию или ошибку. */
  def parseLine(line: String, number: Int): Either[ValidationError, Transaction] =
    val fields = splitLine(line)
    if line.contains('"') then Left(ValidationError.UnsupportedQuoting(number))
    else if fields.size != 4 then Left(ValidationError.WrongFieldCount(number, fields.size))
    else validate(RawRecord(fields(0), fields(1), fields(2), fields(3)), number)
