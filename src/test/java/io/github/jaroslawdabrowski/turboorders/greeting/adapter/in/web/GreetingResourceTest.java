package io.github.jaroslawdabrowski.turboorders.greeting.adapter.in.web;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;

@QuarkusTest
class GreetingResourceTest {

    @Test
    void rejectsRequestsWithoutCredentials() {
        given()
          .when().get("/api/hello")
          .then()
             .statusCode(401);
    }

    @Test
    void greetsAuthenticatedUsers() {
        given()
          .auth().preemptive().basic("turboorders", "changeit")
          .when().get("/api/hello")
          .then()
             .statusCode(200)
             .body("servedBy", is("turboorders-backend"));
    }
}