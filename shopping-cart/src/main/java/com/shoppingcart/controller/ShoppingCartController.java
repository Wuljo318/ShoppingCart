
package com.shoppingcart.controller;

import com.shoppingcart.dto.AddCartItemRequest;
import com.shoppingcart.dto.CartResponse;
import com.shoppingcart.dto.SubmitCartResponse;
import com.shoppingcart.service.ShoppingCartService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/customers/{customerId}/cart")
public class ShoppingCartController {

    private final ShoppingCartService service;

    public ShoppingCartController(ShoppingCartService service) {
        this.service = service;
    }

    @GetMapping
    public CartResponse getCart(@PathVariable @NotBlank String customerId) {
        return CartResponse.from(service.getCart(customerId));
    }

    @PostMapping("/items")
    @ResponseStatus(HttpStatus.CREATED)
    public CartResponse addItem(
            @PathVariable @NotBlank String customerId,
            @Valid @RequestBody AddCartItemRequest request
    ) {
        return CartResponse.from(service.addItem(customerId, request));
    }

    @DeleteMapping("/items/{itemId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void removeItem(
            @PathVariable @NotBlank String customerId,
            @PathVariable @NotBlank String itemId
    ) {
        service.removeItem(customerId, itemId);
    }

    @DeleteMapping
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void evictCart(@PathVariable @NotBlank String customerId) {
        service.evictCart(customerId);
    }

    @PostMapping("/submit")
    @ResponseStatus(HttpStatus.CREATED)
    public SubmitCartResponse submitCart(@PathVariable @NotBlank String customerId) {
        return SubmitCartResponse.from(service.submitCart(customerId));
    }
}
