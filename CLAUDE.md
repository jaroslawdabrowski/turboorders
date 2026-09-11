# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

TurboOrders: an order-management tool for a friend's cosmetics e-commerce shop, meant to streamline how he takes and processes orders. Currently in an early scaffolding phase - the app itself just shows a toolbar and a translated greeting; the point of this phase was to get the full toolchain (Quarkus/hexagonal backend, Angular frontend, Basic Auth, Terraform-provisioned serverless AWS infra, i18n) wired up end-to-end before building real order-management features on top.

Single Maven module at the repo root (not a `backend/`/`frontend/` split): Java under `src/main/java`, config under `src/main/resources`, Angular app at Quinoa's default `src/main/webui`. Quinoa builds the Angular app and serves it from the same Quarkus artifact.

Code and comments are in English. The UI is bilingual (Polish/English) via `@ngx-translate`, **default language Polish**.

## Commands

Backend (run from the repo root):
- `./mvnw quarkus:dev` - dev mode; Quinoa also runs `ng serve` and proxies frontend requests; `quarkus-amazon-dynamodb`'s Dev Services auto-starts a local DynamoDB (via a Localstack testcontainer) - no manual docker-compose needed. **Do not add `-Plambda` here** - see "Dev mode vs. the Lambda extension" below.
- `./mvnw test` - full backend test suite (also exercises the Dev Services DynamoDB via `@QuarkusTest`).
- `./mvnw test -Dtest=GreetingResourceTest` - single test class; `-Dtest=ClassName#methodName` for a single method.
- `./mvnw package -Plambda` - builds the deployable app. Produces `target/turboorders-*-runner.jar` + `target/lib/` (legacy-jar layout) **and** `target/function.zip`, the flattened classpath archive the Lambda container image is built from. The `lambda` profile is what actually pulls in `quarkus-amazon-lambda-http` - see below for why it's not a plain dependency. `scripts/build.sh` already passes `-Plambda`.

Frontend (run from `src/main/webui/`, only needed standalone - normally Quinoa drives it):
- `npm start` / `ng serve` - dev server on `:4200` (no working backend behind `/api` unless Quarkus is also running).
- `npm test` / `ng test` - Karma/Jasmine unit tests.
- `npm run build` / `ng build` - production build to `dist/webui/browser`.

Deployment (local machine only for now; see `infra/main/versions.tf` and `scripts/deploy.sh` for the one-time bootstrap sequence):
- `scripts/build.sh` - `mvn package` then builds the Lambda container image from `target/function.zip` via `src/main/docker/Dockerfile.lambda`.
- `scripts/deploy.sh` - pushes that image to ECR and runs `terraform apply` in `infra/main`.

Java 21; Node must satisfy Angular 20's engine check (`^20.19.0 || ^22.12.0 || >=24.0.0` - note plain `24.0.x`-`24.14.x` does **not** satisfy Angular CLI 22+'s narrower requirement, which is why this repo is pinned to Angular 20).

## Architecture

### Hexagonal, package-by-feature

Everything lives under `io.github.jaroslawdabrowski.turboorders`, structured domain → port → application → adapter, mirroring a sibling project's style but deliberately kept to Quarkus defaults (one module, no `backend/`/`frontend/` split):

```
greeting/                 the only bounded context so far - deliberately trivial (phase 1
                           is a hello-world page), but establishes the pattern future
                           contexts (orders, products, customers, ...) should follow
  domain/                 Greeting record - no framework annotations
  port/in/                GetGreetingUseCase
  application/             GreetingService - implements the use case, no ports/out needed yet
  adapter/in/web/          GreetingResource (JAX-RS, @Authenticated) + GreetingResponse (wire DTO)

platform/security/         Basic Auth, cross-cutting, outside the greeting hexagon -
                           BasicAuthIdentityProvider, single shared user, no roles
```

When adding a real bounded context (orders, etc.), follow `greeting/`'s shape: domain records with no framework annotations, a `port/in` interface per use case, an `application` service implementing it, and adapters that depend inward. Add `port/out` only once a context actually needs an external dependency (a repository, an external API) - `greeting` doesn't, so it has none.

### Dev mode vs. the Lambda extension

**`quarkus-amazon-lambda-http` is a Maven profile (`-Plambda`), not a plain dependency** - deliberately, to work around a genuine bug in this exact extension combination. With it on the classpath, `./mvnw quarkus:dev` crashes on the very first boot with `IllegalArgumentException: Key already registered quarkus.http.local-base-uri` (immediately followed by a second one for `quarkus.http.port`), thrown from `io.quarkus.runtime.ValueRegistryImpl`. Root cause: the Lambda extension's dev-mode poll loop (`AbstractLambdaPollLoop.startPollLoop`) and Quinoa's live-coding forward proxy (`ForwardedDevProcessor`, only active in dev mode) both register the same well-known value-registry keys unconditionally, with no guard against a key already being set - confirmed reproducible on a fully clean environment (no stale processes/containers) and on two separate Quarkus platform versions (3.39.2 and 3.39.3), so it isn't leftover local state or a version fluke. `./mvnw test` never hits it because Quinoa's forward proxy doesn't activate outside dev mode.

Keeping the extension out of the default dependency set fixes this entirely - `quarkus:dev` and `./mvnw test` both run clean. It only needs to be present when actually packaging for Lambda deployment, hence `-Plambda` (see `scripts/build.sh`). **Don't move `quarkus-amazon-lambda-http` back into the main `<dependencies>` block** without re-verifying this collision is fixed upstream first.

### Security

Single shared user, Basic Auth, no roles - `BasicAuthIdentityProvider` (`platform/security/`) validates against `turboorders.security.username` / `turboorders.security.password-hash` (BCrypt) and builds the identity with `QuarkusSecurityIdentity.builder()` directly rather than a hand-rolled `SecurityIdentity` implementation. `quarkus.http.auth.permission.authenticated.paths=/api/*` gates all API routes; the static frontend is unauthenticated (the login page itself has to load before there's anything to authenticate with).

**`io.quarkus:quarkus-security` must be an explicit Maven dependency**, not just pulled in transitively - without it `@Authenticated` and the HTTP auth permission config are silently no-ops (every request gets through regardless of credentials, no warning logged). Check "Installed features" in the startup log includes `security` if auth ever seems to stop enforcing.

**BCrypt hash gotcha**: `io.quarkus.elytron.security.common.BcryptUtil.matches` (wildfly-elytron under the hood) only accepts `$2a$`-prefixed hashes - a hash generated by a non-Java bcrypt library (e.g. `bcryptjs`) typically comes out as `$2b$` and throws `InvalidKeySpecException: ELY08003: Unknown crypt string algorithm` at verification time. Swap the prefix to `$2a$` (safe for ASCII passwords under 72 bytes - 2a/2b differ only in an edge-case length-counting bug) rather than trying to get BcryptUtil to generate the hash itself outside a running JVM.

### AWS Lambda packaging

Build with `./mvnw package -Plambda` (see "Dev mode vs. the Lambda extension" above for why the extension is profile-gated). The `quarkus-amazon-lambda-http` extension **requires `quarkus.package.jar.type=legacy-jar`** (the default) - forcing `fast-jar` fails the build with an explicit error from `FunctionZipProcessor`. Don't "fix" the packaging type if it looks inconsistent with other Quarkus projects; legacy-jar + `target/function.zip` is correct here. `src/main/docker/Dockerfile.lambda` builds the container image by unzipping `function.zip` straight into `/var/task` on the AWS `public.ecr.aws/lambda/java:21` base image, with `io.quarkus.amazon.lambda.runtime.QuarkusStreamHandler::handleRequest` as the handler. `.dockerignore` allowlists `target/function.zip` explicitly - it excludes everything else under `target/` by default.

Test the container locally with the Lambda base image's built-in RIE before deploying: `docker run -p 9000:8080 <image>`, then `POST http://localhost:9000/2015-03-31/functions/function/invocations` with a JSON body shaped like an API Gateway v2 / Function URL event (`version`, `rawPath`, `headers`, `requestContext.http.{method,path}`, `isBase64Encoded`).

### Persistence: DynamoDB, not SQL

No Flyway, no JPA/Hibernate - `quarkus-amazon-dynamodb` only. This was a deliberate cost-driven pivot away from the more typical SQL+Flyway pattern: DynamoDB's pay-per-request billing is effectively free at this app's traffic level, whereas even the smallest Aurora/RDS instance has a real fixed monthly cost. `quarkus.dynamodb.aws.region` is the only static config; table name and access come from the Lambda execution role + `aws_dynamodb_table.app` in Terraform. Dev Services (`quarkus-amazon-dynamodb`'s built-in Localstack-based testcontainer) covers local dev and `@QuarkusTest` automatically - there is no docker-compose file and none is needed.

### AWS infrastructure: serverless, no VPC/ALB/ECS

`infra/bootstrap/` (own local state, applied once, manually) creates only the S3 bucket + DynamoDB table used as the Terraform remote state backend for everything else. `infra/main/` is the actual stack: ECR repo, IAM role, the DynamoDB table, the Lambda function (`package_type = "Image"`), and a Lambda Function URL (`authorization_type = "NONE"` at the AWS layer - Basic Auth is enforced inside the app, not by AWS). No VPC, no NAT gateway, no ALB, no CloudFront - Lambda and DynamoDB don't need a VPC, and a Function URL already gets a valid AWS-managed HTTPS certificate on `*.lambda-url.<region>.on.aws` with no owned domain required. This was a deliberate pivot from an initial ECS+ALB plan once "practically free at low traffic" became the explicit priority - ALB alone has an unavoidable ~$16-20/month fixed cost that a Function URL doesn't.

**Chicken-and-egg on first deploy**: `aws_lambda_function.app`'s `image_uri` references an ECR image that has to exist before Terraform can create the function. First-time sequence is `terraform apply -target=aws_ecr_repository.app` (repo only) → `scripts/build.sh && scripts/deploy.sh` (pushes an image) → `terraform apply` (everything else). `scripts/deploy.sh` documents this at the top.

Credentials (`security_username`/`security_password_hash`) are required Terraform variables with no default, marked `sensitive` - supply them via `TF_VAR_security_username`/`TF_VAR_security_password_hash` env vars or a gitignored `infra/main/terraform.tfvars` (see `terraform.tfvars.example`). They land as plain Lambda environment variables (`TURBOORDERS_SECURITY_USERNAME`/`TURBOORDERS_SECURITY_PASSWORD_HASH`) - MicroProfile Config's env var mapping picks them up automatically from the dotted `turboorders.security.*` property names.

### Frontend

Standalone Angular 20 components with signals, no NgModules. Angular Material (M3, `provideAnimationsAsync()`). `@ngx-translate/core` v18 has a **signal-based API that differs from older ngx-translate** - `TranslateService.currentLang` is a signal (`this.translate.currentLang()`), not a plain string property; `provideTranslateService({ lang, fallbackLang, loader })` replaces the old `TranslateModule.forRoot()`. `provideTranslateHttpLoader({ prefix: '/i18n/', suffix: '.json' })` matches Quinoa's `public/i18n/{pl,en}.json` (served at the site root, not the ngx-translate default `/assets/i18n/`).

`AuthService`/`authInterceptor`/`authGuard` (`core/`): Basic Auth header in `sessionStorage`, attached to every `/api/*` request; `authGuard` redirects to `/login` when nothing is stored. `LanguageService` is **client-side only for now** (persists the chosen language to `localStorage`, defaults to `pl`) - there's deliberately no backend language-preference endpoint yet since phase 1 has no real per-user state to justify one.

`Home` (`home/`) calls `GET /api/hello` on load purely to prove the Basic Auth + Lambda + frontend wiring works end-to-end; the greeting text itself is static, translated UI copy (`home.greeting` in the i18n files), not the backend response body.
