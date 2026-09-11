package io.github.jaroslawdabrowski.turboorders.greeting.adapter.in.web;

import io.github.jaroslawdabrowski.turboorders.greeting.domain.Greeting;
import java.time.Instant;

public record GreetingResponse(String servedBy, Instant servedAt) {

    static GreetingResponse from(Greeting greeting) {
        return new GreetingResponse(greeting.servedBy(), greeting.servedAt());
    }
}
