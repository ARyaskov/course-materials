# Кэш дорогих этапов расчёта. Глава 12 (урок 12.4).

"""
    DiskCache(dir; enabled = true)

Дисковый кэш результатов этапов. Ключ — хеш входа этапа, значение —
сериализованный артефакт. Кэш нужен там, где вход воспроизводимо
определяет выход: любой скрытый источник изменчивости (время, случайное
зерно вне конфигурации, содержимое каталога) делает кэш опасным.
"""
mutable struct DiskCache
    dir::String
    enabled::Bool
    hits::Int
    misses::Int
    writes::Int
end

function DiskCache(dir::AbstractString; enabled::Bool = true)
    return DiskCache(String(dir), enabled, 0, 0, 0)
end

"""
    cache_key(parts...) -> String

Ключ кэша: SHA-256 от канонического текстового представления всех частей.
В ключ входят имя этапа, хеш конфигурации, версия пакета и ключи
результатов, от которых этап зависит. Версия обязательна: изменившийся
алгоритм должен обесценить старые записи.
"""
function cache_key(parts...)
    ctx = SHA.SHA256_CTX()
    for p in parts
        SHA.update!(ctx, codeunits(_key_repr(p)))
        SHA.update!(ctx, UInt8[0x1f])
    end
    return bytes2hex(SHA.digest!(ctx))[1:16]
end

_key_repr(x::AbstractString) = String(x)
_key_repr(x::Symbol) = String(x)
_key_repr(x::Real) = repr(x)
_key_repr(x::AbstractDict) = canonical_toml(x)
_key_repr(x::AbstractVector) = join(map(_key_repr, x), ",")
_key_repr(x::Tuple) = join(map(_key_repr, x), ",")
_key_repr(x) = sprint(show, x)

"""
Метка формата записи: меняется, когда меняется способ хранения.
"""
const CACHE_MAGIC = :poincare_cache_v1

"""
Путь к файлу записи кэша по ключу.
"""
cache_path(c::DiskCache, key::AbstractString) = joinpath(c.dir, key * ".jls")

"""
    cached(f, cache, key; force = false)

Вернуть результат `f()`, взяв его из кэша, если запись существует.
При `force = true` значение вычисляется заново и запись обновляется.

Повреждённая или несовместимая запись (например, оставшаяся от другой
версии пакета) не должна ломать прогон: она удаляется, и значение
считается заново.
"""
function cached(f, c::DiskCache, key::AbstractString; force::Bool = false)
    c.enabled || return (value = f(), hit = false)
    path = cache_path(c, key)
    if !force && isfile(path)
        try
            entry = open(deserialize, path)
            # Метка обязательна: `deserialize` на произвольных байтах чаще
            # возвращает мусор, чем бросает исключение.
            entry isa NamedTuple && get(entry, :magic, nothing) === CACHE_MAGIC ||
                error("чужой формат записи кэша")
            c.hits += 1
            return (; value = entry.value, hit = true)
        catch err
            err isa InterruptException && rethrow()
            @warn "запись кэша повреждена и удалена" path exception = err
            rm(path; force = true)
        end
    end
    c.misses += 1
    value = f()
    mkpath(c.dir)
    tmp = path * ".tmp"
    open(io -> serialize(io, (; magic = CACHE_MAGIC, value)), tmp, "w")
    mv(tmp, path; force = true)   # атомарная замена: незавершённая запись не видна
    c.writes += 1
    return (; value, hit = false)
end

"""
    invalidate!(cache; key = nothing)

Удалить запись кэша или очистить кэш целиком.
"""
function invalidate!(c::DiskCache; key::Union{Nothing,AbstractString} = nothing)
    isdir(c.dir) || return 0
    if key !== nothing
        path = cache_path(c, key)
        isfile(path) || return 0
        rm(path)
        return 1
    end
    files = filter(endswith(".jls"), readdir(c.dir; join = true))
    foreach(rm, files)
    return length(files)
end

"""
    cache_stats(cache) -> NamedTuple

Статистика использования: попадания, промахи, объём на диске.
"""
function cache_stats(c::DiskCache)
    files = isdir(c.dir) ? filter(endswith(".jls"), readdir(c.dir; join = true)) : String[]
    bytes = isempty(files) ? 0 : sum(filesize, files)
    total = c.hits + c.misses
    return (;
        c.hits,
        c.misses,
        c.writes,
        entries = length(files),
        bytes,
        hit_rate = total == 0 ? 0.0 : c.hits / total,
    )
end

function Base.show(io::IO, ::MIME"text/plain", c::DiskCache)
    s = cache_stats(c)
    return print(
        io,
        "DiskCache(",
        c.dir,
        c.enabled ? "" : ", отключён",
        "): ",
        s.entries,
        " записей, ",
        round(s.bytes / 1024; digits = 1),
        " КиБ, ",
        "попаданий ",
        s.hits,
        "/",
        s.hits + s.misses,
    )
end
