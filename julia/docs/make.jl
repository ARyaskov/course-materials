using Documenter
using Poincare

DocMeta.setdocmeta!(Poincare, :DocTestSetup, :(using Poincare); recursive = true)

makedocs(;
    modules = [Poincare],
    authors = "Andrei Riaskov",
    sitename = "Poincare.jl",
    remotes = nothing,
    format = Documenter.HTML(;
        edit_link = nothing,
        repolink = "https://github.com/ARyaskov/course-materials/tree/main/julia",
        assets = String[],
        size_threshold = 400 * 1024,
    ),
    pages = [
        "Начало" => "index.md",
        "Расчётный стенд" => ["Конфигурация" => "config.md", "Пайплайн" => "pipeline.md"],
        "Справочник" => [
            "Численное ядро" => "numerics.md",
            "Модели" => "models.md",
            "Идентификация" => "identification.md",
            "Неопределённость" => "uq.md",
        ],
    ],
    # Предупреждение сборки — это ошибка: битая ссылка или незакрытая
    # ссылка на несуществующую функцию не должна попадать в релиз.
    warnonly = false,
    doctest = true,
    checkdocs = :exports,
)
