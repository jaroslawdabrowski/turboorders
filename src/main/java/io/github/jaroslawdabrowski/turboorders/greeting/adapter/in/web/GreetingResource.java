package io.github.jaroslawdabrowski.turboorders.greeting.adapter.in.web;

import io.github.jaroslawdabrowski.turboorders.greeting.port.in.GetGreetingUseCase;
import io.quarkus.security.Authenticated;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/api/hello")
@Authenticated
public class GreetingResource {

    @Inject
    GetGreetingUseCase getGreetingUseCase;

    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public GreetingResponse hello() {
        return GreetingResponse.from(getGreetingUseCase.greet());
    }
}
