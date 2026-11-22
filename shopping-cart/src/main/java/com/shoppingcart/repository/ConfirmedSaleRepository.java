package com.shoppingcart.repository;

import com.shoppingcart.model.ConfirmedSale;
import org.springframework.data.mongodb.repository.MongoRepository;

public interface ConfirmedSaleRepository extends MongoRepository<ConfirmedSale, String> {
}
