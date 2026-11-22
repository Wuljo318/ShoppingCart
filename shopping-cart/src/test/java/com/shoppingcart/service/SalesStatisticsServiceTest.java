package com.shoppingcart.service;

import com.shoppingcart.model.ActionType;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.*;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.aggregation.*;

import java.time.Instant;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class SalesStatisticsServiceTest {

    @Mock
    private MongoTemplate mongoTemplate;

    @InjectMocks
    private SalesStatisticsService service;

    private final Instant from = Instant.parse("2026-01-01T00:00:00Z");
    private final Instant to = Instant.parse("2026-02-01T00:00:00Z");

    private void mockResult(Document document) {
        AggregationResults<Document> results = new AggregationResults<>(
                document == null ? List.of() : List.of(document),
                new Document());

        when(mongoTemplate.aggregate(
                any(Aggregation.class),
                eq("confirmed_sales"),
                eq(Document.class)
        )).thenReturn(results);
    }

    @Test
    void noMatchingSales_ReturnsZero() {
        mockResult(null);

        long count = service.countSoldOffers(
                "offer-1", ActionType.ADD, from, to);

        assertEquals(0L, count);
    }

    @Test
    void matchingSales_ReturnsCorrectCount() {
        mockResult(new Document("count", 8));

        long count = service.countSoldOffers(
                "offer-1", ActionType.ADD, from, to);

        assertEquals(8L, count);
    }

    @Test
    void largeCount_ReturnsLongValue() {
        mockResult(new Document("count", 3_000_000_000L));

        long count = service.countSoldOffers(
                "offer-1", ActionType.MODIFY, from, to);

        assertEquals(3_000_000_000L, count);
    }

    @Test
    void usesCorrectMongoCollection() {
        mockResult(new Document("count", 1));

        service.countSoldOffers("offer-1", ActionType.DELETE, from, to);

        verify(mongoTemplate).aggregate(
                any(Aggregation.class),
                eq("confirmed_sales"),
                eq(Document.class));
    }

    @Test
    void aggregationContainsCorrectFilters() {
        mockResult(null);

        service.countSoldOffers("my-offer", ActionType.MODIFY, from, to);

        ArgumentCaptor<Aggregation> captor =
                ArgumentCaptor.forClass(Aggregation.class);

        verify(mongoTemplate).aggregate(
                captor.capture(),
                eq("confirmed_sales"),
                eq(Document.class));

        List<Document> pipeline =
                captor.getValue().toPipeline(Aggregation.DEFAULT_CONTEXT);

        String json = pipeline.toString();

        assertTrue(json.contains("soldAt"));
        assertTrue(json.contains("my-offer"));
        assertTrue(json.contains("MODIFY"));
        assertTrue(json.contains("$unwind"));
        assertTrue(json.contains("$count"));
    }

    @Test
    void aggregationUsesExclusiveUpperTimeBound() {
        mockResult(null);

        service.countSoldOffers("offer-1", ActionType.ADD, from, to);

        ArgumentCaptor<Aggregation> captor =
                ArgumentCaptor.forClass(Aggregation.class);

        verify(mongoTemplate).aggregate(
                captor.capture(),
                eq("confirmed_sales"),
                eq(Document.class));

        String json = captor.getValue()
                .toPipeline(Aggregation.DEFAULT_CONTEXT).toString();

        assertTrue(json.contains("$gte"));
        assertTrue(json.contains("$lt"));
    }

    @Test
    void fractionalStartBoundaryRoundsUpToMillisecond() {
        mockResult(null);

        Instant fractional = Instant.parse("2026-01-01T00:00:00.000000001Z");

        service.countSoldOffers(
                "offer-1", ActionType.ADD, fractional, to);

        ArgumentCaptor<Aggregation> captor =
                ArgumentCaptor.forClass(Aggregation.class);

        verify(mongoTemplate).aggregate(
                captor.capture(),
                eq("confirmed_sales"),
                eq(Document.class));

        List<Document> pipeline =
                captor.getValue().toPipeline(Aggregation.DEFAULT_CONTEXT);

        Document match = (Document) pipeline.get(0).get("$match");
        Document soldAt = (Document) match.get("soldAt");
        Date lowerBound = (Date) soldAt.get("$gte");

        assertEquals(Instant.parse("2026-01-01T00:00:00.001Z"),
                lowerBound.toInstant());
    }
}
