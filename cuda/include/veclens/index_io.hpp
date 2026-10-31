#pragma once
// Сериализация индекса. Формат простой и выровненный: заголовок, затем
// секции подряд. Загрузка не требует пересборки списков.

#include <cstdint>
#include <memory>
#include <string>

#include "veclens/ivf_index.hpp"

namespace veclens {

inline constexpr std::uint32_t kIndexMagic = 0x564C4E53u;  // "VLNS"
inline constexpr std::uint32_t kIndexVersion = 3u;

#pragma pack(push, 8)
struct IndexFileHeader {
  std::uint32_t magic = kIndexMagic;
  std::uint32_t version = kIndexVersion;
  std::int32_t dim = 0;
  std::int32_t dim_padded = 0;
  std::int32_t nlist = 0;
  std::int32_t metric = 0;
  std::int32_t storage = 0;
  std::int32_t reserved = 0;
  std::int64_t n_vectors = 0;
  std::uint64_t centroids_offset = 0;
  std::uint64_t offsets_offset = 0;
  std::uint64_t data_offset = 0;
  std::uint64_t ids_offset = 0;
  std::uint64_t total_bytes = 0;
};
#pragma pack(pop)

class IndexSerializer {
public:
  static void save(const IvfFlatIndex& index, const std::string& path);
  // Возвращается указатель, а не значение: у индекса есть пользовательский
  // деструктор, поэтому неявного перемещения у него нет, а объявлять его
  // ради одной функции загрузки было бы лишним.
  static std::unique_ptr<IvfFlatIndex> load(const std::string& path);
  static IndexFileHeader read_header(const std::string& path);
};

}  // namespace veclens
