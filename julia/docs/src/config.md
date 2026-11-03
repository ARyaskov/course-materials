```@meta
CurrentModule = Poincare
```

# Конфигурация и CLI

Схема конфигурации, разбор TOML, хеш прогона, командный интерфейс и кэш этапов.

```@docs
CLIOptions
ConfigError
DataSection
DiskCache
IdentificationSection
ModelSection
OutputSection
RunConfig
RunSection
SolverSection
UQSection
apply_override!
build_config
build_model
cache_key
cache_path
cache_stats
cached
canonical_toml
check_consistency
config_hash
invalidate!
julia_main
load_config
main
model_parameter_names
parse_args
parse_override
save_config
section_from
to_dict
```
