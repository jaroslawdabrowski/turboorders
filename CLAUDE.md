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

**Function URL public access needs two `aws_lambda_permission` resources, not one.** Since October 2025 AWS requires a `NONE`-auth Function URL's resource policy to grant *both* `lambda:InvokeFunctionUrl` *and* `lambda:InvokeFunction` - without the second one, every request 403s with `AccessDeniedException` before ever reaching the app (confirmed by direct testing: no propagation delay, no amount of retrying fixes it, only adding the second permission does). AWS's own recommended policy scopes that second grant with a `lambda:InvokedViaFunctionUrl` condition, but `aws_lambda_permission` doesn't expose that condition key yet ([hashicorp/terraform-provider-aws#44829](https://github.com/hashicorp/terraform-provider-aws/issues/44829)), so `aws_lambda_permission.public_invoke` in `main.tf` grants plain public `lambda:InvokeFunction` instead - broader than AWS's ideal (anyone with AWS credentials could directly `Invoke` the function via the API, not just through the URL), but Basic Auth inside the app is the real access boundary either way, so this is an accepted gap until the provider catches up.

**Redeploying to the same image tag silently no-ops.** `aws_lambda_function.app.image_uri` is a plain string (`<repo>:<tag>`); Lambda resolves a tag to a digest once, at deploy time, and never re-checks it, and Terraform only diffs the `image_uri` string itself, not the image's actual content - so pushing a new image to the same tag (e.g. always `:latest`) and re-running `terraform apply` produces "No changes", leaving the *old* code running with no error or warning. `scripts/build.sh` tags every build uniquely (git short SHA, `-dirty` suffix if the working tree has uncommitted changes, falling back to a timestamp outside a git repo) and writes it to `target/.image-tag`; `scripts/deploy.sh` reads that file so both scripts agree on the tag without the caller having to pass one. Don't "simplify" this back to a fixed tag - always verify a deploy actually changed something by checking the `terraform apply` plan shows `~ image_uri` before trusting a deploy did anything.

**`infra/iam/terraform-user-policy.json`** is the least-privilege IAM policy for whichever user/role runs Terraform + `scripts/deploy.sh` (deliberately not `AdministratorAccess`) - scoped to exactly the actions this stack's resources need, by ARN prefix (`turboorders-*`) where AWS's API supports resource-level scoping. Paste it into IAM → Policies → Create policy → JSON when setting up a new deploy identity. A few actions had to be added empirically because Terraform's `aws_*` resources read more sub-state on refresh than their `Create*` action alone implies (e.g. `dynamodb:DescribeContinuousBackups`/`DescribeTimeToLive` after `CreateTable`, `logs:DescribeLogGroups` after `CreateLogGroup` - the latter needs `Resource: "*"` since the API itself takes no log-group-name parameter to scope against) - if a future resource type is added to `infra/main` and `terraform apply` 403s on a read (not just a write), that's almost always the shape of the fix: add the missing read action, not a broader resource pattern. **A partially-failed `apply` leaves the successfully-created resource `tainted`** (Terraform assumes the whole resource is suspect when *any* call during its creation errors, even a trailing read) - `terraform plan` then wants to destroy and recreate something that's already fine; run `terraform untaint <resource address>` instead of letting it delete/recreate real infrastructure.

### Frontend

Standalone Angular 20 components with signals, no NgModules. Angular Material (M3, `provideAnimationsAsync()`). `@ngx-translate/core` v18 has a **signal-based API that differs from older ngx-translate** - `TranslateService.currentLang` is a signal (`this.translate.currentLang()`), not a plain string property; `provideTranslateService({ lang, fallbackLang, loader })` replaces the old `TranslateModule.forRoot()`. `provideTranslateHttpLoader({ prefix: '/i18n/', suffix: '.json' })` matches Quinoa's `public/i18n/{pl,en}.json` (served at the site root, not the ngx-translate default `/assets/i18n/`).

`AuthService`/`authInterceptor`/`authGuard` (`core/`): Basic Auth header in `sessionStorage`, attached to every `/api/*` request; `authGuard` redirects to `/login` when nothing is stored. `LanguageService` is **client-side only for now** (persists the chosen language to `localStorage`, defaults to `pl`) - there's deliberately no backend language-preference endpoint yet since phase 1 has no real per-user state to justify one.

**Visual style**: a warm, muted "premium cosmetics packaging" palette - `--to-cream`/`--to-cream-elevated`/`--to-ink`/`--to-ink-soft`/`--to-gold`/`--to-gold-soft`/`--to-blush` custom properties on `:root` in `styles.scss`, used directly (not through Material's token system) for surfaces the app fully controls: the toolbar, card accent borders, and wordmarks. Prefer `--mat-sys-*` tokens for anything Material renders itself; mixing the two on the same element is how this breaks later (see the pvopt reference project's own `--pv-*` convention this mirrors). `.to-serif` (Playfair Display, loaded in `index.html` - chosen over an earlier Cormorant Garamond pass as a closer match to Didot, the high-contrast serif associated with French luxury/fashion branding) is for headings/wordmarks only - body text and Material controls stay on Roboto. **`mat-button`'s own theme classes (e.g. `.mat-unthemed`) win over a plain `color` on the button** - they're higher specificity and, for at least the toolbar's language-switcher button, don't actually route through the `--mdc-text-button-label-text-color` token the way Material's docs imply; overriding a `mat-button`'s text color reliably needs both a more specific selector and `!important` (see `.app-toolbar .lang-button` in `app.scss`) - verify with the browser's computed-style inspector (or `getComputedStyle`) rather than assuming a token override took effect, since the wrong color here fails silently (renders, just unreadable) rather than erroring.

`Home` (`home/`) calls `GET /api/hello` on load purely to prove the Basic Auth + Lambda + frontend wiring works end-to-end; the greeting text itself is static, translated UI copy (`home.greeting` in the i18n files), not the backend response body.

**`mat-card-header`/`mat-card-content` have zero padding on the seam between them** (`mat-card-header` ships `padding-bottom: 0`, `mat-card-content` ships `padding-top: 0`) - fine for a short header, but `login.scss`'s custom `mat-card-title` (Playfair Display, larger font/line-height than Material's default) made the title sit flush against the first `mat-form-field`'s outline with no breathing room. Fixed with an explicit `mat-card-header { padding-bottom: 1rem; }` in `login.scss`. If a future card-based component looks like its header text is crowding the content right below it, check this seam first with `getComputedStyle` before assuming it's a spacing bug elsewhere.

### Local tooling: Playwright MCP

`.mcp.json` wires up `@playwright/mcp` for driving/screenshotting the app in a real browser. It's configured with `--output-dir /tmp/turboorders-playwright-mcp` **specifically so screenshots, traces, and page snapshots don't land in the repo root or `.playwright-mcp/`** - without that flag the server defaults to writing there, and it's easy to end up with stray `*.png` files and a `.playwright-mcp/` dir showing up as untracked in `git status`. Don't drop that flag; if it ever looks removed, that's a regression, not a simplification.
