package io.github.jaroslawdabrowski.turboorders.platform.security;

import io.quarkus.elytron.security.common.BcryptUtil;
import io.quarkus.security.AuthenticationFailedException;
import io.quarkus.security.identity.AuthenticationRequestContext;
import io.quarkus.security.identity.IdentityProvider;
import io.quarkus.security.identity.SecurityIdentity;
import io.quarkus.security.identity.request.UsernamePasswordAuthenticationRequest;
import io.quarkus.security.runtime.QuarkusSecurityIdentity;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Single shared user, no roles - matches this app's "one user for the whole team" auth model.
 */
@ApplicationScoped
public class BasicAuthIdentityProvider implements IdentityProvider<UsernamePasswordAuthenticationRequest> {

    @ConfigProperty(name = "turboorders.security.username")
    String configuredUsername;

    @ConfigProperty(name = "turboorders.security.password-hash")
    String configuredPasswordHash;

    @Override
    public Class<UsernamePasswordAuthenticationRequest> getRequestType() {
        return UsernamePasswordAuthenticationRequest.class;
    }

    @Override
    public Uni<SecurityIdentity> authenticate(UsernamePasswordAuthenticationRequest request,
            AuthenticationRequestContext context) {
        String username = request.getUsername();
        String password = new String(request.getPassword().getPassword());

        if (!configuredUsername.equals(username) || !BcryptUtil.matches(password, configuredPasswordHash)) {
            return Uni.createFrom().failure(new AuthenticationFailedException());
        }

        SecurityIdentity identity = QuarkusSecurityIdentity.builder()
                .setPrincipal(() -> username)
                .setAnonymous(false)
                .build();
        return Uni.createFrom().item(identity);
    }
}
