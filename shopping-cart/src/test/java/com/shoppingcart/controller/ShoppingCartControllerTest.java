package com.shoppingcart.controller;

import com.shoppingcart.dto.*;
import com.shoppingcart.model.*;
import com.shoppingcart.service.ShoppingCartService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.*;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ShoppingCartControllerTest {

    @Mock
    private ShoppingCartService service;

    @InjectMocks
    private ShoppingCartController controller;

    @Test
    void getCart_ReturnsCorrectCustomer() {
        ShoppingCart cart = new ShoppingCart("customer-1");
        when(service.getCart("customer-1")).thenReturn(cart);

        CartResponse response = controller.getCart("customer-1");

        assertEquals("customer-1", response.customerId());
        assertTrue(response.items().isEmpty());
        verify(service).getCart("customer-1");
    }

    @Test
    void getCart_ReturnsExistingItems() {
        ShoppingCart cart = new ShoppingCart("customer-1");
        cart.getItems().add(new CartItem(
                "item-1", "offer-1", ActionType.ADD,
                List.of(new OneTimePrice(BigDecimal.TEN))));

        when(service.getCart("customer-1")).thenReturn(cart);

        CartResponse response = controller.getCart("customer-1");

        assertEquals(1, response.items().size());
        assertEquals("item-1", response.items().get(0).id());
        assertEquals("offer-1", response.items().get(0).offerId());
    }

    @Test
    void getCart_ResponseItemsAreImmutable() {
        ShoppingCart cart = new ShoppingCart("customer-1");
        when(service.getCart("customer-1")).thenReturn(cart);

        CartResponse response = controller.getCart("customer-1");

        assertThrows(UnsupportedOperationException.class,
                () -> response.items().clear());
    }

    @Test
    void addItem_CallsServiceWithCorrectParameters() {
        AddCartItemRequest request = new AddCartItemRequest(
                "offer-1", ActionType.ADD,
                List.of(new OneTimePrice(BigDecimal.TEN)));

        when(service.addItem("customer-1", request))
                .thenReturn(new ShoppingCart("customer-1"));

        CartResponse response = controller.addItem("customer-1", request);

        assertEquals("customer-1", response.customerId());
        verify(service).addItem("customer-1", request);
    }

    @Test
    void removeItem_CallsService() {
        controller.removeItem("customer-1", "item-1");

        verify(service).removeItem("customer-1", "item-1");
        verifyNoMoreInteractions(service);
    }

    @Test
    void evictCart_CallsService() {
        controller.evictCart("customer-1");

        verify(service).evictCart("customer-1");
        verifyNoMoreInteractions(service);
    }

    @Test
    void submitCart_ReturnsCorrectResponse() {
        Instant timestamp = Instant.parse("2026-11-21T12:00:00Z");

        ConfirmedSale sale = new ConfirmedSale(
                "order-1", "customer-1", timestamp, List.of());

        when(service.submitCart("customer-1")).thenReturn(sale);

        SubmitCartResponse response = controller.submitCart("customer-1");

        assertEquals("order-1", response.orderId());
        assertEquals("customer-1", response.customerId());
        assertEquals("SUBMITTED", response.status());
        assertEquals(timestamp, response.submittedAt());

        verify(service).submitCart("customer-1");
    }
}
