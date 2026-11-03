"""
    Poincare

Расчётный стенд курса «Язык Julia для научных вычислений»: численное ядро,
предметные модели (механика, теплофизика, биология), решатели, идентификация
параметров, оценка неопределённости, отчёты и CLI.

Пакет зависит только от стандартной библиотеки Julia; графика подключается
расширением `PoincareMakieExt` при наличии `Makie`.
"""
module Poincare

using Dates
using DelimitedFiles
using InteractiveUtils
using LinearAlgebra
using Logging
using Printf
using Random
using SHA
using Serialization
using SparseArrays
using Statistics
using TOML

include("macros.jl")
include("numerics.jl")
include("quadrature.jl")
include("nonlinear.jl")
include("types.jl")
include("linalg.jl")
include("structures.jl")
include("ode.jl")
include("models/oscillator.jl")
include("models/rotor.jl")
include("models/bio.jl")
include("models/heat.jl")
include("models/wave.jl")
include("optimize.jl")
include("identification.jl")
include("viz.jl")
include("config.jl")
include("cache.jl")
include("uq.jl")
include("datapipeline.jl")
include("observability.jl")
include("report.jl")
include("cli.jl")

export @check_physical, @timed_stage, @unstable_warn
export Grid1D, nodes
export l2_norm, linf_norm, rel_error
export first_derivative, first_derivative!
export second_derivative, second_derivative!
export convergence_orders, convergence_study
export chebyshev_nodes, barycentric_weights, barycentric_eval
export trapezoid, simpson, gauss_legendre, adaptive_simpson, integrate
export bisect, newton, brent, newton_system, RootResult

export AbstractModel, AbstractDynamicModel, AbstractFieldModel
export AbstractProblem, ODEProblem, Solution, component
export AbstractSolver, AbstractODESolver, ExplicitEuler, Midpoint, RK4
export solve
export AdaptiveRK, ButcherTableau, bs23, dp54
export Rotor, steady_amplitude, steady_phase, steady_solution, sweep
export LotkaVolterra, LogLotkaVolterra, SIR, MichaelisMenten
export BladeSection, BladeModel, CoolingChannel
export levenberg_marquardt, LMResult, ParameterScaling
export Measurements, IdentificationSetup, IdentificationResult, identify
export FigureData, FigureRegistry, save_figure_data, register!, write_index
export plot_resonance, plot_solution, plot_residuals, plot_field, plot_convergence
export report_figures, poincare_theme
export Oscillator, natural_frequency, damping_ratio, total_energy
export LinearFit, weighted_lsq, lsq, robust_lsq, tikhonov, correlation_matrix
export cg, laplace1d_sparse, laplace2d_sparse, LaplaceOperator2D
export Beam, assemble, modal_analysis, ModalResult, mode_shape, static_deflection
export RunConfig, load_config, build_config, config_hash, save_config, build_model
export ConfigError, DiskCache, cached, cache_key, invalidate!, cache_stats
export ParameterSpace, UniformDist, NormalDist, LogNormalDist
export propagate, UQResult, sobol_indices, SobolResult, posterior_space
export Stage, RunContext, RunResult, run_pipeline, standard_pipeline, run_directory
export check_tolerances, ToleranceCheck, summarize_runs, main
export RunLogger, TeeLogger, LogRecord, log_progress, parse_log, log_summary

public rhs!, initial_state, parameters, with_parameters, check_model_interface
public order, nstages, step!, analytic_solution
public rk_step!, error_norm, propose_step, hermite_interp, check_order_conditions
public critical_speed_rpm, quality_factor, frequency_ratio, peak_speed
public settling_time, regime_report
public equilibrium, lv_invariant, from_log, basic_reproduction, peak_infected
public final_size, mm_implicit_time, qss_validity
public grid_norms, richardson
public HeatRod, NeumannRod, WaveString, grid, total_heat, biot
public heat_step!, heat_explicit, implicit_heat, max_stable_dt, laplacian2d!
public classify, diffusivity, steady_temperature, max_metal_temperature
public heat_balance, dittus_boelter, with_coolant_speed
public max_temperature_at_speed, required_coolant_speed, mesh_study
public wave_energy, wave_leapfrog, wave_step_size, numerical_phase_velocity
public points_per_wavelength, axial_stress
public to_scaled, from_scaled, covariance, stderr_of, identifiability
public residual_diagnostics, huber_weights, latin_hypercube, count_basins
public multistart_confidence, differential_evolution
public parameters_of, model_at, to_θ, from_θ, span
public ResidualFunction, chi2_reduced, report, synthetic_measurements
public resonance_data, solution_data, residual_data, field_data, convergence_data
public validate_figures
public fd_weights, fd_stencil, apply_stencil!, gauss_legendre_rule
public converged, root_tolerance, finite_jacobian
public chi2_reduced, significance, stagnated, detect_structure, smart_factorize
public section_area, section_inertia, bending_stiffness, linear_density, total_mass
public ndofs, node_coordinates, fixed_dofs, element_stiffness, element_mass
public exact_frequencies, eigenvalue_sensitivity
public ConvergenceError, StabilityError, assert_finite, assert_nonnegative
public canonical_toml, apply_override!, parse_override, section_from, to_dict
public model_parameter_names, check_consistency, RunSection, DataSection
public ModelSection, SolverSection, IdentificationSection, UQSection, OutputSection
public cache_path, quantile_of, mean_of, transform, halton, sample_unit
public relative_spread, posterior_samples, delta_method, quantity_of_interest
public validate_pipeline, output_path, write_manifest, succeeded, StageFailure
public stage_data, stage_solution, stage_identification, stage_uq, stage_report
public all_within_tolerance, write_report, parse_args, CLIOptions, julia_main
public run_metrics, write_metrics

end # module Poincare
