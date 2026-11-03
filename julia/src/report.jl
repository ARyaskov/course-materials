# Отчёт о прогоне и проверка допусков. Глава 12 (уроки 12.3, 12.9).

"""
    ToleranceCheck

Результат проверки одного допуска: имя величины, значение, предел, вердикт.
"""
struct ToleranceCheck
    name::Symbol
    value::Float64
    limit::Float64
    ok::Bool
    comment::String
end

"""
    check_tolerances(ctx) -> Vector{ToleranceCheck}

Проверка результатов прогона по допускам из секции `[output.tolerance]`.
Поддерживаются:

  - `chi2` — верхняя граница приведённого `χ²/ν`;
  - `stderr_pct` — максимальная относительная погрешность параметра, %;
  - `condition` — верхняя граница обусловленности якобиана;
  - `spread_pct` — максимальный относительный разброс целевой величины, %.

Расчёт без объявленных допусков — не результат, а набор чисел: пока
не сказано, какое расхождение считается приемлемым, проверить нечего.
"""
function check_tolerances(ctx::RunContext)
    tol = ctx.config.output.tolerance
    checks = ToleranceCheck[]
    isempty(tol) && return checks

    if haskey(ctx, :identification)
        r = ctx[:identification]
        if haskey(tol, :chi2)
            v = chi2_reduced(r)
            push!(
                checks,
                ToleranceCheck(
                    :chi2, v, tol[:chi2], v ≤ tol[:chi2], "согласие модели с данными"
                ),
            )
        end
        if haskey(tol, :stderr_pct)
            rel = 100 .* r.stderr ./ abs.(r.estimate)
            i = argmax(rel)
            push!(
                checks,
                ToleranceCheck(
                    :stderr_pct,
                    rel[i],
                    tol[:stderr_pct],
                    rel[i] ≤ tol[:stderr_pct],
                    "худший параметр: $(r.parameters[i])",
                ),
            )
        end
        if haskey(tol, :condition)
            push!(
                checks,
                ToleranceCheck(
                    :condition,
                    r.condition,
                    tol[:condition],
                    r.condition ≤ tol[:condition],
                    "обусловленность якобиана",
                ),
            )
        end
    end
    if haskey(ctx, :uq) && haskey(tol, :spread_pct)
        u = ctx[:uq].uq
        v = 100 * relative_spread(u)
        push!(
            checks,
            ToleranceCheck(:spread_pct, v, tol[:spread_pct], v ≤ tol[:spread_pct], u.name),
        )
    end
    return checks
end

"""
Все проверки допусков пройдены.
"""
all_within_tolerance(checks) = all(c -> c.ok, checks)

"""
    stage_report(ctx) -> String

Этап отчёта: Markdown-файл с конфигурацией, таймингами, результатами
идентификации, оценкой неопределённости и проверкой допусков.
Возвращает путь к файлу.
"""
function stage_report(ctx::RunContext)
    path = joinpath(ctx.dir, "report.md")
    checks = check_tolerances(ctx)
    open(path, "w") do io
        return write_report(io, ctx, checks)
    end
    ctx.config.output.figures && _write_figure_data(ctx)
    return path
end

"""
    write_report(io, ctx, checks = check_tolerances(ctx))

Записать отчёт о прогоне в поток `io` в формате Markdown.
"""
function write_report(io::IO, ctx::RunContext, checks = check_tolerances(ctx))
    cfg = ctx.config
    println(io, "# Прогон «", cfg.run.name, "» — ", cfg.digest, "\n")
    println(io, "| поле | значение |")
    println(io, "|------|----------|")
    println(io, "| начат | ", ctx.started, " |")
    println(io, "| конфигурация | `", cfg.source, "` |")
    println(io, "| модель | `", cfg.model.kind, "` |")
    println(io, "| Julia | ", VERSION, ", потоков ", Threads.nthreads(), " |")
    println(io, "| Poincare | ", _package_version(), " |")
    println(io, "| зерно | ", cfg.run.seed, " |\n")

    _report_stages(io, ctx)
    haskey(ctx, :data) && _report_data(io, ctx)
    haskey(ctx, :identification) && _report_identification(io, ctx)
    haskey(ctx, :uq) && _report_uq(io, ctx)
    _report_tolerances(io, checks)
    _report_reproduction(io, ctx)
    return nothing
end

function _report_stages(io::IO, ctx::RunContext)
    println(io, "## Этапы\n")
    println(io, "| этап | время, с | память, МиБ | кэш |")
    println(io, "|------|---------:|------------:|:---:|")
    for t in ctx.timings
        @printf(
            io,
            "| %s | %.3f | %.1f | %s |\n",
            t.stage,
            t.seconds,
            t.bytes / 2^20,
            t.hit ? "да" : "—"
        )
    end
    # Этап отчёта формирует эту таблицу и своего времени в ней ещё не знает.
    @printf(
        io,
        "| **всего (без отчёта)** | **%.3f** | | |\n\n",
        sum(t -> t.seconds, ctx.timings; init = 0.0)
    )
end

function _report_data(io::IO, ctx::RunContext)
    ms = ctx[:data]
    println(io, "## Измерения\n")
    for m in ms
        @printf(
            io,
            "- `%s`: %d точек, t ∈ [%.4g, %.4g], компонента %d, σ = %.3g\n",
            m.label,
            length(m),
            first(m.t),
            last(m.t),
            m.component,
            first(m.σ)
        )
    end
    return println(io)
end

function _report_identification(io::IO, ctx::RunContext)
    r = ctx[:identification]
    println(io, "## Идентификация\n")
    println(
        io,
        "Статус: `",
        r.status,
        "`, вызовов невязки: ",
        r.ncalls,
        ", χ²/ν = ",
        round(chi2_reduced(r); digits = 3),
        " (ν = ",
        r.dof,
        "), cond(J) = ",
        round(r.condition; sigdigits = 3),
        "\n",
    )
    println(io, "| параметр | оценка | σ | отн., % |")
    println(io, "|----------|-------:|--:|--------:|")
    for (i, name) in enumerate(r.parameters)
        @printf(
            io,
            "| %s | %.6g | %.4g | %.2f |\n",
            name,
            r.estimate[i],
            r.stderr[i],
            100 * r.stderr[i] / abs(r.estimate[i])
        )
    end
    println(io)
    n = length(r.parameters)
    strong = [
        (r.parameters[i], r.parameters[j], r.correlation[i, j]) for i in 1:n for
        j in (i + 1):n if abs(r.correlation[i, j]) > 0.9
    ]
    if !isempty(strong)
        println(io, "Сильные корреляции оценок:\n")
        for (a, b, ρ) in strong
            @printf(io, "- `%s` ↔ `%s`: %+.3f\n", a, b, ρ)
        end
        println(io)
    end
    d = residual_diagnostics(r.residuals)
    return d.structured && println(
        io,
        "> Остатки имеют структуру: модель не описывает ",
        "часть наблюдаемого эффекта.\n",
    )
end

function _report_uq(io::IO, ctx::RunContext)
    a = ctx[:uq]
    u = a.uq
    println(io, "## Неопределённость\n")
    println(
        io,
        "Целевая величина: **",
        a.name,
        "**; метод `",
        ctx.config.uq.method,
        "`, точек ",
        length(u.samples),
        u.nfailed > 0 ? " (неудачных $(u.nfailed))" : "",
        "\n",
    )
    @printf(io, "- среднее: %.6g ± %.3g (стандартная ошибка среднего)\n", u.mean, u.se)
    @printf(
        io, "- стандартное отклонение: %.6g (%.2f %%)\n", u.std, 100 * u.std / abs(u.mean)
    )
    for (q, v) in zip(u.levels, u.quantiles)
        @printf(io, "- квантиль %.3g: %.6g\n", q, v)
    end
    println(io)
    if a.sobol !== nothing
        s = a.sobol
        println(io, "### Вклады в дисперсию\n")
        println(io, "| параметр | Sᵢ | S_Tᵢ | взаимодействия |")
        println(io, "|----------|---:|-----:|---------------:|")
        for (i, n) in enumerate(s.names)
            @printf(
                io,
                "| %s | %.3f | %.3f | %.3f |\n",
                n,
                s.first[i],
                s.total[i],
                s.total[i] - s.first[i]
            )
        end
        println(io)
    end
end

function _report_tolerances(io::IO, checks)
    isempty(checks) && return nothing
    println(io, "## Допуски\n")
    println(io, "| величина | значение | предел | вердикт | примечание |")
    println(io, "|----------|---------:|-------:|:-------:|------------|")
    for c in checks
        @printf(
            io,
            "| %s | %.4g | %.4g | %s | %s |\n",
            c.name,
            c.value,
            c.limit,
            c.ok ? "ок" : "**отказ**",
            c.comment
        )
    end
    println(io)
    all_within_tolerance(checks) || println(io, "> Прогон не прошёл проверку допусков.\n")
    return nothing
end

function _report_reproduction(io::IO, ctx::RunContext)
    println(io, "## Воспроизведение\n")
    println(io, "```bash")
    println(io, "julia --project=. -e 'using Poincare; Poincare.main()' \\")
    println(io, "    run --config ", joinpath(ctx.dir, "config.toml"))
    println(io, "```\n")
    return println(
        io,
        "Конфигурация сохранена рядом с результатами в каноническом виде; ",
        "её хеш `",
        ctx.config.digest,
        "` совпадает с именем каталога.",
    )
end

# Данные фигур готовятся всегда, отрисовка — задача расширения графики.
function _write_figure_data(ctx::RunContext)
    reg = FigureRegistry(ctx.dir)
    cfg = ctx.config
    model = build_model(cfg)
    if model isa Rotor
        register!(
            reg,
            "resonance",
            nothing,
            resonance_data(model);
            caption = "Резонансная кривая ротора",
        )
    end
    haskey(ctx, :solution) && register!(
        reg,
        "solution",
        nothing,
        solution_data(ctx[:solution]);
        caption = "Опорное решение",
    )
    if haskey(ctx, :identification) && haskey(ctx, :data)
        register!(
            reg,
            "residuals",
            nothing,
            residual_data(ctx[:identification], first(ctx[:data]));
            caption = "Остатки подгонки",
        )
    end
    write_index(reg; title = "Рисунки прогона $(cfg.digest)")
    return reg
end

"""
    summarize_runs(dir) -> Vector{NamedTuple}

Сводка по каталогу с результатами: имя, хеш, статус, время. Используется
при сборе результатов параметрического прогона.
"""
function summarize_runs(dir::AbstractString)
    rows = NamedTuple[]
    isdir(dir) || return rows
    for entry in sort(readdir(dir; join = true))
        manifest = joinpath(entry, "manifest.toml")
        isfile(manifest) || continue
        m = TOML.parsefile(manifest)["run"]
        push!(
            rows,
            (;
                name = m["name"],
                digest = m["digest"],
                status = m["status"],
                elapsed = m["elapsed_s"],
                dir = entry,
            ),
        )
    end
    return rows
end
