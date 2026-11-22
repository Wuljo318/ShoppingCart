package com.shoppingcart.controller;

import com.shoppingcart.model.ActionType;
import com.shoppingcart.service.SalesStatisticsService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.*;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class SalesStatisticsControllerTest {

    @Mock
    private SalesStatisticsService service;

    @InjectMocks
    private SalesStatisticsController controller;

    private final Instant from = Instant.parse("2026-01-01T00:00:00Z");
    private final Instant to = Instant.parse("2026-02-01T00:00:00Z");

    @Test
    void getSales_ReturnsCount() {
        when(service.countSoldOffers("offer-1", ActionType.ADD, from, to))
                .thenReturn(17L);

        var result = controller.getSales("offer-1", ActionType.ADD, from, to);

        assertEquals(17L, result.count());
        verify(service).countSoldOffers("offer-1", ActionType.ADD, from, to);
    }

    @Test
    void getSales_NoSales_ReturnsZero() {
        var result = controller.getSales(
                "unknown", ActionType.DELETE, from, to);

        assertEquals(0L, result.count());
    }

    @Test
    void getSales_EqualTimeBoundsRejected() {
        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.getSales("offer-1", ActionType.ADD, from, from));

        assertEquals(HttpStatus.BAD_REQUEST, exception.getStatusCode());
        verifyNoInteractions(service);
    }

    @Test
    void getSales_ReversedTimeBoundsRejected() {
        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.getSales("offer-1", ActionType.ADD, to, from));

        assertEquals(HttpStatus.BAD_REQUEST, exception.getStatusCode());
        verifyNoInteractions(service);
    }

    @Test
    void getSales_AllActionsPassedToService() {
        for (ActionType action : ActionType.values()) {
            controller.getSales("offer-1", action, from, to);
            verify(service).countSoldOffers("offer-1", action, from, to);
        }
    }
}
