package io.github.jaroslawdabrowski.turboorders.greeting.domain;

import java.time.Instant;

public record Greeting(String servedBy, Instant servedAt) {
}
