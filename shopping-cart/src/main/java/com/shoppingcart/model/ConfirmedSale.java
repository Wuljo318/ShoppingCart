package com.shoppingcart.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.Instant;
import java.util.List;

@Document(collection = "confirmed_sales")
public class ConfirmedSale {

    @Id
    private String id;

    private String customerId;
    private Instant soldAt;
    private List<CartItem> items;

    public ConfirmedSale() {
    }

    public ConfirmedSale(String id, String customerId, Instant soldAt, List<CartItem> items) {
        this.id = id;
        this.customerId = customerId;
        this.soldAt = soldAt;
        this.items = items;
    }

    public String getId() {
        return id;
    }

    public String getCustomerId() {
        return customerId;
    }

    public Instant getSoldAt() {
        return soldAt;
    }

    public List<CartItem> getItems() {
        return items;
    }
}
