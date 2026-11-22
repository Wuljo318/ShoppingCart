
package com.shoppingcart.service;

import com.shoppingcart.dto.AddCartItemRequest;
import com.shoppingcart.exception.CartItemNotFoundException;
import com.shoppingcart.exception.EmptyCartException;
import com.shoppingcart.model.CartItem;
import com.shoppingcart.model.ConfirmedSale;
import com.shoppingcart.model.ShoppingCart;
import com.shoppingcart.repository.ConfirmedSaleRepository;
import com.shoppingcart.repository.ShoppingCartRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Service
public class ShoppingCartService {

    private final ShoppingCartRepository repository;
    private final ConfirmedSaleRepository confirmedSaleRepository;

    public ShoppingCartService(ShoppingCartRepository repository, ConfirmedSaleRepository confirmedSaleRepository) {
        this.repository = repository;
        this.confirmedSaleRepository = confirmedSaleRepository;
    }

    public ShoppingCart getCart(String customerId) {
        return repository.findById(customerId)
                .orElseGet(() -> new ShoppingCart(customerId));
    }

    public ShoppingCart addItem(String customerId, AddCartItemRequest request) {
        ShoppingCart cart = getCart(customerId);

        CartItem item = new CartItem(
                UUID.randomUUID().toString(),
                request.offerId(),
                request.action(),
                List.copyOf(request.prices())
        );

        cart.getItems().add(item);

        return repository.save(cart);
    }

    public void removeItem(String customerId, String itemId) {
        ShoppingCart cart = repository.findById(customerId)
                .orElseThrow(() -> new CartItemNotFoundException(itemId));

        boolean removed = cart.getItems().removeIf(item -> item.id().equals(itemId));

        if (!removed) {
            throw new CartItemNotFoundException(itemId);
        }

        repository.save(cart);
    }

    public void evictCart(String customerId) {
        repository.findById(customerId).ifPresent(repository::delete);
    }

    @Transactional
    public ConfirmedSale submitCart(String customerId) {
        ShoppingCart cart = repository.findById(customerId)
                .orElseThrow(EmptyCartException::new);

        if (cart.getItems().isEmpty()) {
            throw new EmptyCartException();
        }

        ConfirmedSale sale = new ConfirmedSale(
                UUID.randomUUID().toString(),
                customerId,
                Instant.now(),
                List.copyOf(cart.getItems())
        );

        confirmedSaleRepository.save(sale);
        repository.delete(cart);

        return sale;
    }
}
