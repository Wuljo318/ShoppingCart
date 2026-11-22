package com.shoppingcart.dto;

import com.shoppingcart.model.ConfirmedSale;

import java.time.Instant;

public record SubmitCartResponse(
        String orderId,
        String customerId,
        String status,
        Instant submittedAt
) {

    public static SubmitCartResponse from(ConfirmedSale sale) {
        return new SubmitCartResponse(sale.getId(), sale.getCustomerId(), "SUBMITTED", sale.getSoldAt());
    }
}
