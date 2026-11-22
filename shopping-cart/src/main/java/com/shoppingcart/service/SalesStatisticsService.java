package com.shoppingcart.service;

import com.shoppingcart.model.ActionType;
import org.bson.Document;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.aggregation.Aggregation;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;

@Service
public class SalesStatisticsService {

    private final MongoTemplate mongoTemplate;

    public SalesStatisticsService(MongoTemplate mongoTemplate) {
        this.mongoTemplate = mongoTemplate;
    }

    public long countSoldOffers(String offerId, ActionType action, Instant from, Instant to) {
        Criteria period = Criteria.where("soldAt").gte(toMongoBoundary(from)).lt(toMongoBoundary(to));
        Criteria item = Criteria.where("items.offerId").is(offerId).and("items.action").is(action.name());

        Aggregation aggregation = Aggregation.newAggregation(
                Aggregation.match(period),
                Aggregation.unwind("items"),
                Aggregation.match(item),
                Aggregation.count().as("count")
        );

        Document result = mongoTemplate.aggregate(aggregation, "confirmed_sales", Document.class)
                .getUniqueMappedResult();

        return result == null ? 0L : result.get("count", Number.class).longValue();
    }

    private static Date toMongoBoundary(Instant instant) {
        Instant millis = instant.truncatedTo(ChronoUnit.MILLIS);
        return Date.from(instant.equals(millis) ? millis : millis.plusMillis(1));
    }
}