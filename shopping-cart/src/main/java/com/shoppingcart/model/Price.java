package com.shoppingcart.model;

import com.fasterxml.jackson.annotation.JsonSubTypes;
import com.fasterxml.jackson.annotation.JsonTypeInfo;

import java.math.BigDecimal;

@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, include = JsonTypeInfo.As.PROPERTY, property = "type")
@JsonSubTypes({
        @JsonSubTypes.Type(value = OneTimePrice.class, name = "ONE_TIME"),
        @JsonSubTypes.Type(value = RecurringPrice.class, name = "RECURRING")
})
public sealed interface Price permits OneTimePrice, RecurringPrice {

    BigDecimal value();
}