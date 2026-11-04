package ledger

/** Единственное место, которое печатает и завершает JVM-процесс. */
@main def run(args: String*): Unit =
  val result = Application.execute(args.toList)
  if result.stdout.nonEmpty then println(result.stdout)
  if result.stderr.nonEmpty then Console.err.println(result.stderr)
  if result.exitCode != 0 then sys.exit(result.exitCode)
