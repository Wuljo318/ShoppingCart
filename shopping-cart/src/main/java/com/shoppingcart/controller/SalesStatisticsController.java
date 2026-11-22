package com.shoppingcart.controller;

import com.shoppingcart.model.ActionType;
import com.shoppingcart.service.SalesStatisticsService;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;

@RestController
@RequestMapping("/api/statistics")
public class SalesStatisticsController {

    private final SalesStatisticsService service;

    public SalesStatisticsController(SalesStatisticsService service) {
        this.service = service;
    }

    @GetMapping("/sales")
    public SalesCount getSales(
            @RequestParam("offerId") @NotBlank String offerId,
            @RequestParam("action") ActionType action,
            @RequestParam("from") Instant from,
            @RequestParam("to") Instant to
    ) {
        if (!from.isBefore(to)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "'from' must be earlier than 'to'.");
        }

        return new SalesCount(service.countSoldOffers(offerId, action, from, to));
    }

    public record SalesCount(long count) {
    }
}