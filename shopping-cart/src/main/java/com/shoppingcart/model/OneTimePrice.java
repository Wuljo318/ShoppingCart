package com.shoppingcart.model;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotNull;
import org.springframework.data.mongodb.core.mapping.Field;
import org.springframework.data.mongodb.core.mapping.FieldType;

import java.math.BigDecimal;

public record OneTimePrice(
        @NotNull
        @DecimalMin("0.00")
        @Digits(integer = 12, fraction = 2)
        @Field(targetType = FieldType.DECIMAL128)
        BigDecimal value
) implements Price {
}