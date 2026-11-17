package com.shoppingcart.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.Version;
import org.springframework.data.mongodb.core.mapping.Document;

import java.util.ArrayList;
import java.util.List;

@Document(collection = "shopping_carts")
public class ShoppingCart {

    @Id
    private String customerId;

    @Version
    private Long version;

    private List<CartItem> items = new ArrayList<>();

    public ShoppingCart() {
    }

    public ShoppingCart(String customerId) {
        this.customerId = customerId;
    }

    public String getCustomerId() {
        return customerId;
    }

    public Long getVersion() {
        return version;
    }

    public List<CartItem> getItems() {
        return items;
    }
}