package com.shoppingcart.model;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;

import java.util.List;

public record CartItem(
        @NotBlank
        String id,

        @NotBlank
        String offerId,

        @NotNull
        ActionType action,

        @NotEmpty
        List<@NotNull @Valid Price> prices
) {
}