package com.shoppingcart.dto;

import com.shoppingcart.model.ActionType;
import com.shoppingcart.model.Price;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;

import java.util.List;

public record AddCartItemRequest(
        @NotBlank
        String offerId,

        @NotNull
        ActionType action,

        @NotEmpty
        List<@NotNull @Valid Price> prices
) {
}