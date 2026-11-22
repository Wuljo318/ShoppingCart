package com.shoppingcart.exception;

public class EmptyCartException extends RuntimeException {

    public EmptyCartException() {
        super("Cannot submit an empty cart.");
    }
}
