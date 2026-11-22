package com.shoppingcart.service;

import com.shoppingcart.dto.AddCartItemRequest;
import com.shoppingcart.exception.CartItemNotFoundException;
import com.shoppingcart.exception.EmptyCartException;
import com.shoppingcart.model.*;
import com.shoppingcart.repository.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.*;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ShoppingCartServiceTest {

    @Mock
    private ShoppingCartRepository repository;

    @Mock
    private ConfirmedSaleRepository saleRepository;

    @InjectMocks
    private ShoppingCartService service;

    private CartItem createItem(String id) {
        return new CartItem(id, "offer-1", ActionType.ADD,
                List.of(new OneTimePrice(new BigDecimal("15.00"))));
    }

    private ShoppingCart createCart(String customerId, CartItem... items) {
        ShoppingCart cart = new ShoppingCart(customerId);
        cart.getItems().addAll(List.of(items));
        return cart;
    }

    private AddCartItemRequest createRequest(ActionType action) {
        return new AddCartItemRequest("offer-1", action,
                List.of(new OneTimePrice(new BigDecimal("15.00"))));
    }

    @Test
    void getCart_WhenCartDoesNotExist_ReturnsEmptyCart() {
        when(repository.findById("customer-1")).thenReturn(Optional.empty());

        ShoppingCart result = service.getCart("customer-1");

        assertEquals("customer-1", result.getCustomerId());
        assertTrue(result.getItems().isEmpty());
        verify(repository, never()).save(any());
    }

    @Test
    void getCart_WhenCartExists_ReturnsExistingCart() {
        ShoppingCart cart = createCart("customer-1", createItem("item-1"));
        when(repository.findById("customer-1")).thenReturn(Optional.of(cart));

        ShoppingCart result = service.getCart("customer-1");

        assertSame(cart, result);
        assertEquals(1, result.getItems().size());
    }

    @ParameterizedTest
    @EnumSource(ActionType.class)
    void addItem_AcceptsEveryActionType(ActionType action) {
        when(repository.findById("customer-1")).thenReturn(Optional.empty());
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        ShoppingCart result = service.addItem("customer-1", createRequest(action));

        assertEquals(1, result.getItems().size());

        CartItem item = result.getItems().get(0);
        assertEquals("offer-1", item.offerId());
        assertEquals(action, item.action());
        assertEquals(new BigDecimal("15.00"), item.prices().get(0).value());
        assertNotNull(UUID.fromString(item.id()));

        verify(repository).save(result);
    }

    @Test
    void addItem_PreservesExistingItems() {
        ShoppingCart cart = createCart("customer-1", createItem("existing"));
        when(repository.findById("customer-1")).thenReturn(Optional.of(cart));
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        ShoppingCart result = service.addItem("customer-1", createRequest(ActionType.ADD));

        assertEquals(2, result.getItems().size());
        assertEquals("existing", result.getItems().get(0).id());
    }

    @Test
    void addItem_GeneratesUniqueIds() {
        when(repository.findById("customer-1")).thenReturn(Optional.empty());
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        String first = service.addItem("customer-1", createRequest(ActionType.ADD))
                .getItems().get(0).id();

        String second = service.addItem("customer-1", createRequest(ActionType.ADD))
                .getItems().get(0).id();

        assertNotEquals(first, second);
    }

    @Test
    void addItem_CopiesPriceList() {
        List<Price> prices = new ArrayList<>();
        prices.add(new OneTimePrice(BigDecimal.ONE));

        AddCartItemRequest request = new AddCartItemRequest(
                "offer-1", ActionType.ADD, prices);

        when(repository.findById("customer-1")).thenReturn(Optional.empty());
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        CartItem item = service.addItem("customer-1", request)
                .getItems().get(0);

        prices.add(new OneTimePrice(BigDecimal.TEN));

        assertEquals(1, item.prices().size());
        assertThrows(UnsupportedOperationException.class,
                () -> item.prices().clear());
    }

    @Test
    void removeItem_RemovesOnlyRequestedItem() {
        ShoppingCart cart = createCart("customer-1",
                createItem("item-1"), createItem("item-2"));

        when(repository.findById("customer-1")).thenReturn(Optional.of(cart));

        service.removeItem("customer-1", "item-1");

        assertEquals(1, cart.getItems().size());
        assertEquals("item-2", cart.getItems().get(0).id());
        verify(repository).save(cart);
    }

    @Test
    void removeItem_WhenCartMissing_ThrowsException() {
        when(repository.findById("customer-1")).thenReturn(Optional.empty());

        assertThrows(CartItemNotFoundException.class,
                () -> service.removeItem("customer-1", "item-1"));

        verify(repository, never()).save(any());
    }

    @Test
    void removeItem_WhenItemMissing_ThrowsException() {
        ShoppingCart cart = createCart("customer-1", createItem("item-1"));
        when(repository.findById("customer-1")).thenReturn(Optional.of(cart));

        assertThrows(CartItemNotFoundException.class,
                () -> service.removeItem("customer-1", "unknown"));

        assertEquals(1, cart.getItems().size());
        verify(repository, never()).save(any());
    }

    @Test
    void evictCart_WhenExists_DeletesCart() {
        ShoppingCart cart = createCart("customer-1");
        when(repository.findById("customer-1")).thenReturn(Optional.of(cart));

        service.evictCart("customer-1");

        verify(repository).delete(cart);
    }

    @Test
    void evictCart_WhenMissing_DoesNothing() {
        when(repository.findById("customer-1")).thenReturn(Optional.empty());

        service.evictCart("customer-1");

        verify(repository, never()).delete(any());
    }

    @Test
    void submitCart_WhenCartMissing_ThrowsException() {
        when(repository.findById("customer-1")).thenReturn(Optional.empty());

        assertThrows(EmptyCartException.class,
                () -> service.submitCart("customer-1"));

        verifyNoInteractions(saleRepository);
        verify(repository, never()).delete(any());
    }

    @Test
    void submitCart_WhenEmpty_ThrowsException() {
        when(repository.findById("customer-1"))
                .thenReturn(Optional.of(createCart("customer-1")));

        assertThrows(EmptyCartException.class,
                () -> service.submitCart("customer-1"));

        verifyNoInteractions(saleRepository);
        verify(repository, never()).delete(any());
    }

    @Test
    void submitCart_SavesSaleBeforeDeletingCart() {
        ShoppingCart cart = createCart("customer-1",
                createItem("item-1"), createItem("item-2"));

        when(repository.findById("customer-1")).thenReturn(Optional.of(cart));

        Instant before = Instant.now();
        ConfirmedSale sale = service.submitCart("customer-1");
        Instant after = Instant.now();

        assertEquals("customer-1", sale.getCustomerId());
        assertNotNull(UUID.fromString(sale.getId()));
        assertEquals(2, sale.getItems().size());
        assertFalse(sale.getSoldAt().isBefore(before));
        assertFalse(sale.getSoldAt().isAfter(after));

        InOrder order = inOrder(saleRepository, repository);
        order.verify(saleRepository).save(sale);
        order.verify(repository).delete(cart);
    }

    @Test
    void submitCart_CreatesImmutableSnapshot() {
        ShoppingCart cart = createCart("customer-1", createItem("item-1"));
        when(repository.findById("customer-1")).thenReturn(Optional.of(cart));

        ConfirmedSale sale = service.submitCart("customer-1");

        cart.getItems().clear();

        assertEquals(1, sale.getItems().size());
        assertThrows(UnsupportedOperationException.class,
                () -> sale.getItems().clear());
    }

    @Test
    void submitCart_WhenSaleSaveFails_DoesNotDeleteCart() {
        ShoppingCart cart = createCart("customer-1", createItem("item-1"));
        when(repository.findById("customer-1")).thenReturn(Optional.of(cart));
        when(saleRepository.save(any())).thenThrow(new IllegalStateException("DB error"));

        assertThrows(IllegalStateException.class,
                () -> service.submitCart("customer-1"));

        verify(repository, never()).delete(any());
    }

    @Test
    void submitCart_WhenCartDeleteFails_PropagatesException() {
        ShoppingCart cart = createCart("customer-1", createItem("item-1"));
        when(repository.findById("customer-1")).thenReturn(Optional.of(cart));
        doThrow(new IllegalStateException("DB error")).when(repository).delete(cart);

        assertThrows(IllegalStateException.class,
                () -> service.submitCart("customer-1"));

        verify(saleRepository).save(any());
    }
}
