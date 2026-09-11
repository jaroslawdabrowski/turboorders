package io.github.jaroslawdabrowski.turboorders.greeting.application;

import io.github.jaroslawdabrowski.turboorders.greeting.domain.Greeting;
import io.github.jaroslawdabrowski.turboorders.greeting.port.in.GetGreetingUseCase;
import jakarta.enterprise.context.ApplicationScoped;
import java.time.Instant;

@ApplicationScoped
public class GreetingService implements GetGreetingUseCase {

    @Override
    public Greeting greet() {
        return new Greeting("turboorders-backend", Instant.now());
    }
}
