### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# Макрос привязки значения к виджету (вставляется Pluto автоматически).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ f0de85a8-e4c8-4b11-8f4d-61e36a037086
md"""
# Отчёт по прогону стенда

Тетрадь — интерфейс к пакету, а не место для расчётной логики.
Всё, что здесь вызывается, живёт в `Poincare.jl` и покрыто тестами;
тетрадь только подбирает параметры и показывает результат.
"""

# ╔═╡ 8f6056ba-05d0-4c26-b020-1fc2bf8e7b60
begin
    using Pkg
    Pkg.activate(@__DIR__)
    using Poincare
    using PlutoUI: PlutoUI
    using CairoMakie: CairoMakie
end

# ╔═╡ 2c1ed104-187e-4657-826d-f6e14dcb82e8
md"""
## Конфигурация

Файл конфигурации задаёт прогон целиком. Изменение любого поля меняет хеш,
а значит — каталог результатов.
"""

# ╔═╡ ffe56d3d-f322-4b67-a571-b77996bef8c6
cfg_path = joinpath(@__DIR__, "..", "configs", "rotor.toml")

# ╔═╡ 4d13e231-8236-4aa2-b98e-7320dee167d3
@bind params PlutoUI.confirm(
    PlutoUI.combine() do Child
        md"""
        Допуск решателя: $(Child("rtol", PlutoUI.Slider([1e-6, 1e-7, 1e-8, 1e-9, 1e-10];
                                                default = 1e-9, show_value = true)))

        Точек выборки: $(Child("nsamples", PlutoUI.Slider(200:200:5000;
                                                  default = 2000, show_value = true)))
        """
    end;
    label = "Выполнить прогон",
)

# ╔═╡ cff16f2c-8456-4c6c-ade4-1f82af357e97
md"""
Хеш прогона: `$(cfg.digest)`. Результаты попадут в `$(run_directory(cfg))`.
"""

# ╔═╡ 6e8d565b-f9d4-4b26-a494-870c6bec7bc7
md"""
## Прогон

Первый расчёт выполняется при открытии тетради. Дальше изменения слайдеров
остаются внутри виджета: `confirm(combine(...))` передаёт новый набор параметров
в расчёт только после нажатия «Выполнить прогон».
"""

# ╔═╡ 3fe19b95-2569-4783-8a24-ae45e5f25992
cfg = load_config(
    cfg_path;
    overrides = Dict(
        "solver.rtol" => params.rtol,
        "uq.nsamples" => params.nsamples,
        "output.dir" => joinpath(@__DIR__, "..", "results"),
    ),
)

# ╔═╡ 5c353d8c-e51d-49b1-8b92-9d3f37495f51
result = run_pipeline(standard_pipeline(), cfg)   # зависит только от cfg

# ╔═╡ 88d6512e-1821-4c6b-81be-0081e8118285
let r = result.context[:identification]
    io = IOBuffer()
    Poincare.report(r; io)
    Base.Text(String(take!(io)))
end

# ╔═╡ c6228a22-f5cd-43ae-8034-5aa88e9c3d91
md"""
## Рисунки

Данные для графиков готовит ядро, отрисовку — расширение `PoincareMakieExt`.
Тетрадь не содержит ни формул, ни численных схем.
"""

# ╔═╡ afcf1de7-6364-46da-8d2f-6f59a7d9850a
first(plot_resonance(build_model(cfg)))

# ╔═╡ e443228b-6de4-4d97-aa64-4f026e8e4491
first(plot_residuals(result.context[:identification], first(result.context[:data])))

# ╔═╡ 58a4a7d8-b335-4113-a0b7-314c67d9b4cf
md"""
## Экспорт

`Export → Static HTML` даёт самодостаточный файл: заказчик расчёта открывает
его в браузере без Julia. Воспроизвести расчёт по такому файлу нельзя —
для этого рядом лежит `config.toml` с хешем прогона.
"""

# ╔═╡ 20773741-a216-443f-84e2-1def9e8b6885
md"""
Расчёт выполнен `Poincare.jl` $(pkgversion(Poincare)) на Julia $(VERSION).
Конфигурация: `$(cfg.digest)`, каталог: `$(run_directory(cfg))`.
"""

# ╔═╡ Cell order:
# ╟─f0de85a8-e4c8-4b11-8f4d-61e36a037086
# ╠═8f6056ba-05d0-4c26-b020-1fc2bf8e7b60
# ╟─2c1ed104-187e-4657-826d-f6e14dcb82e8
# ╠═ffe56d3d-f322-4b67-a571-b77996bef8c6
# ╠═4d13e231-8236-4aa2-b98e-7320dee167d3
# ╟─cff16f2c-8456-4c6c-ade4-1f82af357e97
# ╟─6e8d565b-f9d4-4b26-a494-870c6bec7bc7
# ╠═3fe19b95-2569-4783-8a24-ae45e5f25992
# ╠═5c353d8c-e51d-49b1-8b92-9d3f37495f51
# ╠═88d6512e-1821-4c6b-81be-0081e8118285
# ╟─c6228a22-f5cd-43ae-8034-5aa88e9c3d91
# ╠═afcf1de7-6364-46da-8d2f-6f59a7d9850a
# ╠═e443228b-6de4-4d97-aa64-4f026e8e4491
# ╟─58a4a7d8-b335-4113-a0b7-314c67d9b4cf
# ╟─20773741-a216-443f-84e2-1def9e8b6885
