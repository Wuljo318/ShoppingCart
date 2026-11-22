package com.shoppingcart.dto;

import com.shoppingcart.model.CartItem;
import com.shoppingcart.model.ShoppingCart;

import java.util.List;

public record CartResponse(
        String customerId,
        List<CartItem> items
) {

    public static CartResponse from(ShoppingCart cart) {
        return new CartResponse(cart.getCustomerId(), List.copyOf(cart.getItems()));
    }
}