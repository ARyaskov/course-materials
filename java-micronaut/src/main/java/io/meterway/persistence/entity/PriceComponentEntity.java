package io.meterway.persistence.entity;

import io.meterway.rating.PricingModel;
import io.meterway.rating.PriceTier;
import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.data.annotation.TypeDef;
import io.micronaut.data.model.DataType;
import io.micronaut.serde.annotation.Serdeable;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

/**
 * Ценовая составляющая плана по одной метрике.
 * Ступени хранятся в jsonb: прайс меняется чаще, чем схема, и не заслуживает миграции на каждое изменение.
 */
@Serdeable
@MappedEntity("price_components")
public record PriceComponentEntity(
        @Id UUID id,
        UUID planId,
        String meterCode,
        PricingModel pricingModel,
        BigDecimal includedQuantity,
        @TypeDef(type = DataType.JSON) List<PriceTier> tiers,
        int position
) {
}
