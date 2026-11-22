package com.shoppingcart.model;

import jakarta.validation.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.*;

import java.math.BigDecimal;

import static org.junit.jupiter.api.Assertions.*;

class PriceValidationTest {

    private static Validator validator;

    @BeforeAll
    static void setUp() {
        validator = Validation.buildDefaultValidatorFactory().getValidator();
    }

    private boolean isValid(Object object) {
        return validator.validate(object).isEmpty();
    }

    @ParameterizedTest
    @ValueSource(strings = {"0", "0.00", "0.01", "1.2", "15.99", "999999999999.99"})
    void oneTimePrice_ValidAmounts(String value) {
        assertTrue(isValid(new OneTimePrice(new BigDecimal(value))));
    }

    @ParameterizedTest
    @ValueSource(strings = {"-0.01", "-1", "1.001", "1000000000000", "999999999999.999"})
    void oneTimePrice_InvalidAmounts(String value) {
        assertFalse(isValid(new OneTimePrice(new BigDecimal(value))));
    }

    @Test
    void oneTimePrice_NullValueRejected() {
        assertFalse(isValid(new OneTimePrice(null)));
    }

    @ParameterizedTest
    @ValueSource(strings = {"0", "0.00", "0.01", "15.99", "999999999999.99"})
    void recurringPrice_ValidAmounts(String value) {
        assertTrue(isValid(new RecurringPrice(
                new BigDecimal(value), 12, RecurrenceUnit.MONTH)));
    }

    @ParameterizedTest
    @ValueSource(strings = {"-0.01", "-1", "1.001", "1000000000000"})
    void recurringPrice_InvalidAmounts(String value) {
        assertFalse(isValid(new RecurringPrice(
                new BigDecimal(value), 12, RecurrenceUnit.MONTH)));
    }

    @ParameterizedTest
    @ValueSource(ints = {1, 2, 12, 1000, Integer.MAX_VALUE})
    void recurringPrice_ValidRecurrences(int count) {
        assertTrue(isValid(new RecurringPrice(
                BigDecimal.TEN, count, RecurrenceUnit.MONTH)));
    }

    @ParameterizedTest
    @ValueSource(ints = {-100, -1, 0})
    void recurringPrice_InvalidRecurrences(int count) {
        assertFalse(isValid(new RecurringPrice(
                BigDecimal.TEN, count, RecurrenceUnit.MONTH)));
    }

    @Test
    void recurringPrice_NullValueRejected() {
        assertFalse(isValid(new RecurringPrice(
                null, 12, RecurrenceUnit.MONTH)));
    }

    @Test
    void recurringPrice_NullRecurrencesRejected() {
        assertFalse(isValid(new RecurringPrice(
                BigDecimal.TEN, null, RecurrenceUnit.MONTH)));
    }

    @Test
    void recurringPrice_NullUnitRejected() {
        assertFalse(isValid(new RecurringPrice(
                BigDecimal.TEN, 12, null)));
    }

    @ParameterizedTest
    @EnumSource(RecurrenceUnit.class)
    void recurringPrice_AllUnitsAccepted(RecurrenceUnit unit) {
        assertTrue(isValid(new RecurringPrice(BigDecimal.TEN, 12, unit)));
    }
}
