using Poincare: DiskCache, cached, cache_key, invalidate!, cache_stats, cache_path
using Serialization

@testset "ключ кэша" begin
    @test cache_key(:stage, "abc", "0.1.0") == cache_key(:stage, "abc", "0.1.0")
    @test cache_key(:stage, "abc", "0.1.0") != cache_key(:stage, "abd", "0.1.0")
    @test cache_key(:stage, "abc", "0.1.0") != cache_key(:stage, "abc", "0.2.0")
    @test length(cache_key(:a)) == 16
    d1 = Dict("b" => 2, "a" => 1)
    d2 = Dict("a" => 1, "b" => 2)
    @test cache_key(d1) == cache_key(d2)     # порядок ключей словаря не важен
end

@testset "попадание и промах" begin
    mktempdir() do dir
        cache = DiskCache(joinpath(dir, "c"))
        calls = Ref(0)
        f = () -> (calls[] += 1; sum(1:1000))

        r1 = cached(f, cache, "k1")
        @test !r1.hit && r1.value == 500500 && calls[] == 1

        r2 = cached(f, cache, "k1")
        @test r2.hit && r2.value == 500500 && calls[] == 1   # функция не вызвана

        r3 = cached(f, cache, "k2")
        @test !r3.hit && calls[] == 2

        r4 = cached(f, cache, "k1"; force = true)
        @test !r4.hit && calls[] == 3                        # принудительный пересчёт

        s = cache_stats(cache)
        @test s.hits == 1 && s.misses == 3 && s.entries == 2 && s.bytes > 0
        @test 0 < s.hit_rate < 1
    end
end

@testset "отключённый кэш" begin
    mktempdir() do dir
        cache = DiskCache(joinpath(dir, "c"); enabled = false)
        calls = Ref(0)
        for _ in 1:3
            cached(() -> (calls[] += 1; 1), cache, "k")
        end
        @test calls[] == 3
        @test !isdir(joinpath(dir, "c"))
    end
end

@testset "повреждённая запись" begin
    mktempdir() do dir
        cache = DiskCache(joinpath(dir, "c"))
        cached(() -> 42, cache, "k")
        write(cache_path(cache, "k"), "это не сериализованные данные")
        r = @test_logs (:warn,) match_mode = :any cached(() -> 7, cache, "k")
        @test r.value == 7 && !r.hit          # прогон продолжается, а не падает
        @test cached(() -> 7, cache, "k").hit  # запись восстановлена
    end
end

@testset "инвалидация" begin
    mktempdir() do dir
        cache = DiskCache(joinpath(dir, "c"))
        for k in ("a", "b", "c")
            cached(() -> k, cache, k)
        end
        @test invalidate!(cache; key = "a") == 1
        @test invalidate!(cache; key = "нет") == 0
        @test invalidate!(cache) == 2
        @test cache_stats(cache).entries == 0
    end
end
