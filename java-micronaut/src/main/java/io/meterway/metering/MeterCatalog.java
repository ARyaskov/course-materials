package io.meterway.metering;

import io.meterway.config.MeterDefinition;
import io.meterway.domain.UnknownMeterException;
import jakarta.inject.Singleton;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Каталог метрик. Micronaut подставляет сюда все бины {@link MeterDefinition},
 * созданные из секций {@code meterway.meters.*}: добавление метрики — это правка конфигурации,
 * а не правка кода.
 */
@Singleton
public class MeterCatalog {

    private final Map<String, MeterDefinition> byCode;

    public MeterCatalog(List<MeterDefinition> definitions) {
        this.byCode = definitions.stream()
                .collect(Collectors.toUnmodifiableMap(MeterDefinition::getCode, Function.identity()));
    }

    public MeterDefinition require(String code) {
        MeterDefinition definition = byCode.get(code);
        if (definition == null) {
            throw new UnknownMeterException(code);
        }
        return definition;
    }

    public Optional<MeterDefinition> find(String code) {
        return Optional.ofNullable(byCode.get(code));
    }

    public boolean contains(String code) {
        return byCode.containsKey(code);
    }

    public List<MeterDefinition> all() {
        return List.copyOf(byCode.values());
    }

    /** Метрики, для которых включён контроль квоты. */
    public List<MeterDefinition> quotaEnforced() {
        return byCode.values().stream().filter(MeterDefinition::isQuotaEnforced).toList();
    }

    public int size() {
        return byCode.size();
    }
}
