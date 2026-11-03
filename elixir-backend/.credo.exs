# Конфигурация Credo для проекта.
#
# Строгий режим включён, но две проверки отключены осознанно:
# AliasUsage в тестах даёт шум на однократных обращениях к модулю,
# а ModuleDoc для тестовых модулей смысла не имеет.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "config/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      checks: %{
        disabled: [
          {Credo.Check.Design.AliasUsage, []},
          {Credo.Check.Readability.ModuleDoc, files: %{excluded: ["test/"]}}
        ]
      }
    }
  ]
}
