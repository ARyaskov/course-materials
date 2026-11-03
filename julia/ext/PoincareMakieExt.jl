"""
    PoincareMakieExt

Расширение пакета `Poincare`: построение фигур отчёта средствами Makie.
Загружается автоматически, когда в сессии есть и `Poincare`, и бэкенд Makie
(`CairoMakie`, `GLMakie`, `WGLMakie`).
"""
module PoincareMakieExt

using Poincare
using Makie
using Printf

const P = Poincare

function P.poincare_theme(; fontsize = 18, linewidth = 2)
    return Makie.Theme(;
        fontsize = fontsize,
        figure_padding = 10,
        palette = (
            color = [:steelblue, :firebrick, :seagreen, :darkorange, :purple, :grey40],
            linestyle = [:solid, :dash, :dot, :dashdot],
        ),
        Axis = (
            xgridcolor = (:grey70, 0.35),
            ygridcolor = (:grey70, 0.35),
            xgridwidth = 0.6,
            ygridwidth = 0.6,
            spinewidth = 0.9,
            xtickalign = 1,
            ytickalign = 1,
            titlefont = :regular,
            titlesize = fontsize * 1.05,
        ),
        Lines = (linewidth = linewidth,),
        Scatter = (markersize = 9, strokewidth = 0),
        Legend = (framevisible = false, patchsize = (22, 12)),
    )
end

function P.plot_resonance(
    r::P.Rotor; measurements = nothing, limit = nothing, span = (0.5, 1.6)
)
    fd = P.resonance_data(r; span)
    Ω = fd.columns[:omega]
    A = fd.columns[:amplitude_um]
    ω0 = fd.metadata[:omega0]

    fig = Makie.Figure(; size = (900, 620))
    ax1 = Makie.Axis(fig[1, 1]; ylabel = "амплитуда A, мкм")
    ax2 = Makie.Axis(
        fig[2, 1];
        xlabel = "частота вращения Ω, рад/с",
        ylabel = "фаза φ, град",
        yticks = 0:45:180,
    )
    Makie.linkxaxes!(ax1, ax2)
    Makie.hidexdecorations!(ax1; grid = false)
    Makie.rowsize!(fig.layout, 2, Makie.Relative(0.32))

    Makie.lines!(ax1, Ω, A; color = :steelblue, linewidth = 2.4, label = "модель")
    Makie.lines!(ax2, Ω, fd.columns[:phase_deg]; color = :steelblue, linewidth = 2)
    Makie.vlines!(ax1, [ω0]; color = :grey55, linestyle = :dash)
    Makie.vlines!(ax2, [ω0]; color = :grey55, linestyle = :dash)
    Makie.vlines!(ax1, [r.Ω]; color = :firebrick, linestyle = :dashdot)
    Makie.text!(
        ax1,
        ω0,
        maximum(A) * 0.97;
        text = "ω₀",
        align = (:left, :top),
        offset = (6, 0),
        color = :grey45,
    )

    if limit !== nothing
        Makie.hlines!(ax1, [float(limit)]; color = :firebrick, linestyle = :dot)
    end
    if measurements !== nothing
        Makie.errorbars!(
            ax1,
            measurements.omega,
            measurements.amplitude,
            measurements.sigma;
            color = :black,
            whiskerwidth = 8,
        )
        Makie.scatter!(
            ax1,
            measurements.omega,
            measurements.amplitude;
            color = :black,
            markersize = 9,
            label = "измерения",
        )
    end
    Makie.axislegend(ax1; position = :rt)
    Makie.hidespines!(ax1, :t, :r)
    Makie.hidespines!(ax2, :t, :r)
    return fig, fd
end

function P.plot_solution(
    sol::P.Solution;
    component::Integer = 1,
    scale::Real = 1e6,
    ylabel::AbstractString = "смещение x, мкм",
)
    fd = P.solution_data(sol; component, scale)
    fig = Makie.Figure(; size = (860, 420))
    ax = Makie.Axis(fig[1, 1]; xlabel = "время t, с", ylabel = ylabel)
    Makie.lines!(ax, fd.columns[:t], fd.columns[:value]; color = :steelblue)
    Makie.hidespines!(ax, :t, :r)
    return fig, fd
end

function P.plot_residuals(result::P.IdentificationResult, meas::P.Measurements)
    fd = P.residual_data(result, meas)
    t = fd.columns[:t]
    r = fd.columns[:residual]

    fig = Makie.Figure(; size = (920, 400))
    ax1 = Makie.Axis(fig[1, 1]; xlabel = "время t, с", ylabel = "нормированный остаток")
    Makie.hlines!(
        ax1,
        [-2.0, 0.0, 2.0];
        color = [:grey65, :grey40, :grey65],
        linestyle = [:dot, :solid, :dot],
    )
    Makie.scatter!(ax1, t, r; color = :steelblue, markersize = 5)

    ax2 = Makie.Axis(
        fig[1, 2];
        xlabel = "остаток",
        ylabel = "частота",
        title = @sprintf("χ²/ν = %.3f", fd.metadata[:chi2_reduced])
    )
    Makie.hist!(
        ax2,
        r;
        bins = 30,
        color = (:steelblue, 0.7),
        strokewidth = 0.5,
        strokecolor = :white,
    )
    Makie.colsize!(fig.layout, 2, Makie.Relative(0.32))
    return fig, fd
end

function P.plot_field(m::P.BladeModel, T::AbstractMatrix; limit::Real = 1250.0)
    b = m.section
    x = collect(range(0, b.Lx; length = b.nx)) .* 1e3
    y = collect(range(0, b.Ly; length = b.ny)) .* 1e3
    Tm = copy(float.(T))
    for j in 1:b.ny, i in 1:b.nx
        m.kind[i, j] === P.CHANNEL && (Tm[i, j] = NaN)
    end
    finite = filter(isfinite, vec(Tm))

    fig = Makie.Figure(; size = (960, 420))
    ax = Makie.Axis(
        fig[1, 1]; xlabel = "x, мм", ylabel = "y, мм", aspect = Makie.DataAspect()
    )
    hm = Makie.heatmap!(
        ax, x, y, Tm; colormap = :thermal, colorrange = extrema(finite), nan_color = :white
    )
    Makie.contour!(ax, x, y, Tm; levels = 5, color = (:white, 0.6), linewidth = 0.8)
    maximum(finite) > limit &&
        Makie.contour!(ax, x, y, Tm; levels = [float(limit)], color = :red, linewidth = 2.5)
    Makie.Colorbar(fig[1, 2], hm; label = "T, К")
    return fig, P.field_data(m, T)
end

function P.plot_convergence(
    steps::AbstractVector, errors::AbstractVector; expected_order = nothing
)
    fd = P.convergence_data(steps, errors; expected_order)
    h = fd.columns[:h]
    e = fd.columns[:error]

    fig = Makie.Figure(; size = (680, 480))
    ax = Makie.Axis(
        fig[1, 1]; xscale = log10, yscale = log10, xlabel = "шаг сетки h", ylabel = "ошибка"
    )
    Makie.scatterlines!(ax, h, e; color = :steelblue, markersize = 10, label = "измерено")
    if expected_order !== nothing
        ref = e[1] .* (h ./ h[1]) .^ expected_order
        Makie.lines!(
            ax,
            h,
            ref;
            color = :grey50,
            linestyle = :dash,
            label = "наклон $(expected_order)",
        )
    end
    Makie.axislegend(ax; position = :rb)
    return fig, fd
end

function P.report_figures(
    run_dir::AbstractString;
    rotor = nothing,
    blade = nothing,
    field = nothing,
    result = nothing,
    measurements = nothing,
    theme = P.poincare_theme(),
)
    Makie.set_theme!(theme)
    try
        reg = P.FigureRegistry(run_dir)
        saver = (path, fig; px_per_unit = 3) -> if endswith(path, ".png")
            Makie.save(path, fig; px_per_unit)
        else
            Makie.save(path, fig)
        end

        if rotor !== nothing
            fig, fd = P.plot_resonance(rotor; limit = 70.0)
            P.register!(
                reg,
                "resonance",
                fig,
                fd;
                caption = "Резонансная кривая ротора",
                save_fn = saver,
            )
        end
        if blade !== nothing && field !== nothing
            fig, fd = P.plot_field(blade, field)
            P.register!(
                reg,
                "field",
                fig,
                fd;
                caption = "Стационарное поле температуры сечения",
                formats = (".png",),
                save_fn = saver,
            )
        end
        if result !== nothing && measurements !== nothing
            fig, fd = P.plot_residuals(result, measurements)
            P.register!(
                reg,
                "residuals",
                fig,
                fd;
                caption = "Остатки идентификации",
                save_fn = saver,
            )
        end
        P.write_index(reg)
        return reg
    finally
        Makie.set_theme!()
    end
end

end # module
