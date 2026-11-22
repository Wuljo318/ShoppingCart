package com.shoppingcart.exception;

import org.junit.jupiter.api.Test;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.HttpStatus;

import static org.junit.jupiter.api.Assertions.*;

class ApiExceptionHandlerTest {

    private final ApiExceptionHandler handler = new ApiExceptionHandler();

    @Test
    void missingItem_Returns404() {
        var response = handler.handleNotFound(
                new CartItemNotFoundException("item-1"));

        assertEquals(HttpStatus.NOT_FOUND.value(), response.getStatus());
        assertTrue(response.getDetail().contains("item-1"));
    }

    @Test
    void emptyCart_Returns400() {
        var response = handler.handleEmptyCart(new EmptyCartException());

        assertEquals(HttpStatus.BAD_REQUEST.value(), response.getStatus());
        assertEquals("Cannot submit an empty cart.", response.getDetail());
    }

    @Test
    void duplicateKey_Returns409() {
        var response = handler.handleConflict(
                new DuplicateKeyException("Duplicate key"));

        assertEquals(HttpStatus.CONFLICT.value(), response.getStatus());
    }

    @Test
    void optimisticLockFailure_Returns409() {
        var response = handler.handleConflict(
                new OptimisticLockingFailureException("Conflict"));

        assertEquals(HttpStatus.CONFLICT.value(), response.getStatus());
    }

    @Test
    void conflict_ReturnsExpectedMessage() {
        var response = handler.handleConflict(
                new DuplicateKeyException("Duplicate key"));

        assertTrue(response.getDetail().contains("modified by another request"));
    }
}
