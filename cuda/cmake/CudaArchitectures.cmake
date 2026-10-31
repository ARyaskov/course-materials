# Выбор целевых архитектур GPU.
#
# По умолчанию проект собирается начиная с Turing (sm_75) — это минимальная
# архитектура курса. Список закрывает Turing, Ampere, Ada и Hopper; в конце
# добавляется PTX для самой новой из них, чтобы бинарник запускался и на более
# новых картах через JIT.
#
# Pascal (GTX 10xx, sm_61) поддерживается только CUDA Toolkit 12.x: в CUDA 13.0
# offline-компиляция для Maxwell/Pascal/Volta удалена. Включается опцией
#   cmake -DVECLENS_LEGACY_PASCAL=ON
# Код проекта не использует возможностей выше sm_75 без страховки через
# __CUDA_ARCH__, поэтому сборка для sm_61 корректна.

option(VECLENS_LEGACY_PASCAL "Добавить sm_61 (GTX 10xx); требует CUDA Toolkit 12.x" OFF)

set(VECLENS_DEFAULT_ARCHS "75;86;89;90")

if(VECLENS_LEGACY_PASCAL)
  if(CMAKE_CUDA_COMPILER_VERSION VERSION_GREATER_EQUAL 13.0)
    message(FATAL_ERROR
      "VECLENS_LEGACY_PASCAL=ON требует CUDA Toolkit 12.x: "
      "CUDA ${CMAKE_CUDA_COMPILER_VERSION} больше не компилирует код для sm_61.")
  endif()
  list(PREPEND VECLENS_DEFAULT_ARCHS "61")
endif()

if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES OR CMAKE_CUDA_ARCHITECTURES STREQUAL "")
  set(CMAKE_CUDA_ARCHITECTURES "${VECLENS_DEFAULT_ARCHS}" CACHE STRING "" FORCE)
endif()

# native = архитектура карты, которая стоит в этой машине; удобно для разработки,
# непригодно для дистрибуции.
if(CMAKE_CUDA_ARCHITECTURES STREQUAL "native")
  message(STATUS "veclens: сборка под архитектуру локальной карты (native)")
endif()

# Добавляем PTX старшей архитектуры: карта новее списка запустит код через JIT.
function(veclens_apply_architectures target)
  if(CMAKE_CUDA_ARCHITECTURES STREQUAL "native")
    set_property(TARGET ${target} PROPERTY CUDA_ARCHITECTURES native)
    return()
  endif()
  set(archs "")
  foreach(a IN LISTS CMAKE_CUDA_ARCHITECTURES)
    list(APPEND archs "${a}-real")
  endforeach()
  list(GET CMAKE_CUDA_ARCHITECTURES -1 newest)
  list(APPEND archs "${newest}-virtual")
  set_property(TARGET ${target} PROPERTY CUDA_ARCHITECTURES ${archs})
endfunction()
