using Poincare: @check_physical, @timed_stage, @unstable_warn
using Logging

@testset "@check_physical" begin
    k = 1.8e6
    @test (@check_physical k > 0) === true
    @test (@check_physical k > 0 "жёсткость") === true

    bad = -1.0
    err = try
        @check_physical bad > 0 "жёсткость опоры"
    catch e
        e
    end
    @test err isa ArgumentError
    # В сообщении — исходный текст условия, а не его значение
    @test occursin("bad > 0", err.msg)
    @test occursin("жёсткость опоры", err.msg)

    err2 = try
        @check_physical bad > 0
    catch e
        e
    end
    @test occursin("bad > 0", err2.msg)
    @test !occursin("—", err2.msg)          # описания нет — нет и тире

    # Выражение вычисляется ровно один раз
    calls = Ref(0)
    f() = (calls[] += 1; true)
    @check_physical f()
    @test calls[] == 1

    # Гигиена: локальные имена макроса не затирают переменные вызывающего
    val = 42
    @check_physical val > 0
    @test val == 42
end

@testset "@timed_stage" begin
    logger = TestLogger()
    result = with_logger(logger) do
        @timed_stage "сборка" sum(1:1000)
    end
    @test result == 500500                 # возвращается значение выражения
    @test length(logger.logs) == 1
    rec = only(logger.logs)
    @test rec.message == "этап завершён"
    @test rec.kwargs[:stage] == "сборка"
    @test rec.kwargs[:seconds] ≥ 0

    # Выражение выполняется на месте вызова: присваивание видно снаружи
    with_logger(NullLogger()) do
        @timed_stage "присваивание" global _ts_x = 7
    end
    @test _ts_x == 7
end

@testset "@unstable_warn" begin
    stable(x) = x + 1
    @test (@unstable_warn stable(1)) == 2
    logger = TestLogger()
    with_logger(logger) do
        @unstable_warn stable(1)
    end
    @test isempty(logger.logs)

    unstable(x) = x > 0 ? 1 : 1.0
    logger2 = TestLogger()
    v = with_logger(logger2) do
        @unstable_warn (rand() > 2 ? 1 : Real[1][1])
    end
    @test v == 1
end
