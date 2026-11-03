# Макросы стенда. Их немного, и каждый решает задачу, недоступную функции.
# Глава 2 (урок 2.6).

"""
    @check_physical expr [msg]

Проверка физической корректности. В сообщение попадает исходный текст
условия — обычная функция видит только его значение.

```jldoctest
julia> k = -1.0;

julia> try
           @check_physical k > 0 \"жёсткость опоры\"
       catch err
           println(err.msg)
       end
нарушено физическое ограничение: k > 0 — жёсткость опоры
```
"""
macro check_physical(ex, msg = "")
    exs = string(ex)
    return quote
        local val = $(esc(ex))
        if !val
            throw(
                ArgumentError(
                    string(
                        "нарушено физическое ограничение: ",
                        $exs,
                        isempty($(esc(msg))) ? "" : " — " * $(esc(msg)),
                    ),
                ),
            )
        end
        val
    end
end

"""
    @timed_stage label expr

Выполнить `expr`, сообщив время выполнения структурированной записью
журнала. Возвращает значение `expr`.

Макрос, а не функция, по двум причинам: выражение должно выполняться
на месте вызова (иначе замыкание меняет область видимости переменных),
и метка должна попадать в журнал вместе с результатом.
"""
macro timed_stage(label, ex)
    return quote
        local t0 = time_ns()
        local result = $(esc(ex))
        local dt = (time_ns() - t0) / 1e9
        @info "этап завершён" stage = $(esc(label)) seconds = round(dt; digits = 3)
        result
    end
end

"""
    @unstable_warn expr

Предупредить, если результат выражения имеет неконкретный тип. Полезно
в узких местах: типовая нестабильность обнаруживается на месте, а не
через `@code_warntype` спустя месяц.
"""
macro unstable_warn(ex)
    exs = string(ex)
    return quote
        local result = $(esc(ex))
        isconcretetype(typeof(result)) ||
            @warn "неконкретный тип результата" expr = $exs type = typeof(result)
        result
    end
end
