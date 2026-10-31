#pragma once
// Минимальный каркас тестов. Зависимость на GTest ради десятка проверок —
// это лишние полчаса сборки и лишний внешний пакет в CI, поэтому здесь
// свой header-only harness: регистрация статическим объектом, main в самом
// заголовке под VL_TEST_MAIN.
//
// Использование:
//   #define VL_TEST_MAIN
//   #include "test_main.hpp"
//
//   VL_TEST(имя_теста) {
//     VL_CHECK(2 + 2 == 4);
//     VL_CHECK_NEAR(0.1 + 0.2, 0.3, 1e-9);
//   }

#include <cmath>
#include <cstdio>
#include <cstring>
#include <exception>
#include <stdexcept>
#include <string>
#include <vector>

namespace veclens {
namespace test {

struct Failure : std::runtime_error {
  using std::runtime_error::runtime_error;
};

struct TestCase {
  const char* name;
  void (*fn)();
};

// Функция-обёртка вместо глобальной переменной: порядок инициализации
// статических объектов внутри одной единицы трансляции не определён,
// а локальная статика создаётся при первом обращении.
inline std::vector<TestCase>& registry() {
  static std::vector<TestCase> tests;
  return tests;
}

struct Registrar {
  Registrar(const char* name, void (*fn)()) { registry().push_back(TestCase{name, fn}); }
};

inline void fail(const char* expr, const char* file, int line, const std::string& extra = {}) {
  std::string message = std::string(file) + ':' + std::to_string(line) + ": проверка не прошла: " +
                        expr;
  if (!extra.empty()) message += " (" + extra + ')';
  throw Failure(message);
}

inline void check_near(double a, double b, double eps, const char* expr, const char* file,
                       int line) {
  if (!(std::fabs(a - b) <= eps) || std::isnan(a) || std::isnan(b)) {
    fail(expr, file, line,
         std::to_string(a) + " против " + std::to_string(b) + ", допуск " + std::to_string(eps));
  }
}

}  // namespace test
}  // namespace veclens

#define VL_TEST_CONCAT_INNER(a, b) a##b
#define VL_TEST_CONCAT(a, b) VL_TEST_CONCAT_INNER(a, b)

#define VL_TEST(name)                                                                 \
  static void name();                                                                 \
  static ::veclens::test::Registrar VL_TEST_CONCAT(name, _registrar)(#name, &name);   \
  static void name()

#define VL_CHECK(cond)                                              \
  do {                                                              \
    if (!(cond)) ::veclens::test::fail(#cond, __FILE__, __LINE__);  \
  } while (0)

#define VL_CHECK_NEAR(a, b, eps)                                                                 \
  ::veclens::test::check_near(static_cast<double>(a), static_cast<double>(b),                    \
                              static_cast<double>(eps), #a " ~ " #b, __FILE__, __LINE__)

#if defined(VL_TEST_MAIN)

int main(int argc, char** argv) {
  const auto& tests = ::veclens::test::registry();
  int passed = 0;
  std::vector<std::string> failed;

  for (const auto& test : tests) {
    // Фильтр по подстроке: удобно гонять один тест под compute-sanitizer,
    // где полный набор занимает минуты.
    if (argc > 1 && std::strstr(test.name, argv[1]) == nullptr) continue;

    std::printf("[ RUN  ] %s\n", test.name);
    try {
      test.fn();
      std::printf("[  OK  ] %s\n", test.name);
      ++passed;
    } catch (const std::exception& e) {
      std::printf("[ FAIL ] %s\n         %s\n", test.name, e.what());
      failed.emplace_back(test.name);
    } catch (...) {
      std::printf("[ FAIL ] %s\n         неизвестное исключение\n", test.name);
      failed.emplace_back(test.name);
    }
  }

  std::printf("\nПройдено %d, провалено %zu\n", passed, failed.size());
  for (const std::string& name : failed) std::printf("  провален: %s\n", name.c_str());
  return failed.empty() ? 0 : 1;
}

#endif
