package com.shoppingcart.dto;

import com.shoppingcart.model.*;
import jakarta.validation.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.*;

import java.math.BigDecimal;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;

class AddCartItemRequestTest {

    private static Validator validator;

    @BeforeAll
    static void setUp() {
        validator = Validation.buildDefaultValidatorFactory().getValidator();
    }

    private List<Price> validPrices() {
        return List.of(new OneTimePrice(BigDecimal.TEN));
    }

    private boolean isValid(AddCartItemRequest request) {
        return validator.validate(request).isEmpty();
    }

    @ParameterizedTest
    @EnumSource(ActionType.class)
    void allActionsAccepted(ActionType action) {
        assertTrue(isValid(new AddCartItemRequest(
                "offer-1", action, validPrices())));
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {" ", "   ", "\t", "\n"})
    void blankOfferIdRejected(String offerId) {
        assertFalse(isValid(new AddCartItemRequest(
                offerId, ActionType.ADD, validPrices())));
    }

    @Test
    void missingActionRejected() {
        assertFalse(isValid(new AddCartItemRequest(
                "offer-1", null, validPrices())));
    }

    @Test
    void nullPricesRejected() {
        assertFalse(isValid(new AddCartItemRequest(
                "offer-1", ActionType.ADD, null)));
    }

    @Test
    void emptyPricesRejected() {
        assertFalse(isValid(new AddCartItemRequest(
                "offer-1", ActionType.ADD, List.of())));
    }

    @Test
    void nullPriceElementRejected() {
        assertFalse(isValid(new AddCartItemRequest(
                "offer-1", ActionType.ADD, Arrays.asList((Price) null))));
    }

    @Test
    void negativeNestedPriceRejected() {
        assertFalse(isValid(new AddCartItemRequest(
                "offer-1", ActionType.ADD,
                List.of(new OneTimePrice(new BigDecimal("-1"))))));
    }

    @Test
    void invalidNestedRecurringPriceRejected() {
        assertFalse(isValid(new AddCartItemRequest(
                "offer-1", ActionType.ADD,
                List.of(new RecurringPrice(
                        BigDecimal.TEN, 0, RecurrenceUnit.MONTH)))));
    }

    @Test
    void multipleValidPricesAccepted() {
        assertTrue(isValid(new AddCartItemRequest(
                "offer-1", ActionType.MODIFY,
                List.of(
                        new OneTimePrice(BigDecimal.ONE),
                        new RecurringPrice(BigDecimal.TEN, 12, RecurrenceUnit.MONTH)
                ))));
    }

    @Test
    void validZeroPriceAccepted() {
        assertTrue(isValid(new AddCartItemRequest(
                "offer-1", ActionType.ADD,
                List.of(new OneTimePrice(BigDecimal.ZERO)))));
    }
}
