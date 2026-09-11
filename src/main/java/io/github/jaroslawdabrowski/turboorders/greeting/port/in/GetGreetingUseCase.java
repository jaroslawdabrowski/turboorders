package io.github.jaroslawdabrowski.turboorders.greeting.port.in;

import io.github.jaroslawdabrowski.turboorders.greeting.domain.Greeting;

public interface GetGreetingUseCase {

    Greeting greet();
}
