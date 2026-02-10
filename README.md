# PaddleBilling

Elixir library for Paddle Billing API v2.

Dual-write CRUD, two-way sync with drift detection, webhook verification, checkout flow, and installable admin panel.

## Features

- **Full API client** - Products, Prices, Discounts, Transactions with pagination and rate limit handling
- **Dual-write CRUD** - create/update in Paddle API + local database atomically
- **Two-way sync** - pull from Paddle, push to Paddle, or reconcile with strategy (`:paddle_wins`, `:local_wins`, `:newest_wins`)
- **Drift detection** - SHA256 checksums to detect data divergence
- **Webhook verification** - HMAC-SHA256 signature + replay protection
- **Auto-sync** - webhooks + periodic Oban reconciliation
- **Checkout flow** - Transaction creation + Paddle.js LiveView hook
- **Admin panel** - installable LiveViews for managing products, prices, discounts, and sync

## Requirements

- Elixir 1.15+
- Phoenix LiveView 0.20+
- Req (HTTP client)
- Oban (background jobs)
- PostgreSQL

## Installation

### 1. Add as a dependency

Add `paddle_billing` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:paddle_billing, github: "safemyprivacy0-bit/paddle_billing"}
  ]
end
```

### 2. Configure environment variables

```bash
export PADDLE_BILLING_ENVIRONMENT=sandbox    # or "production"
export PADDLE_BILLING_API_KEY=pdl_sdbx_apikey_xxx
export PADDLE_BILLING_CLIENT_TOKEN=test_xxx  # for Paddle.js checkout
export PADDLE_BILLING_SIGNING_SECRET=pdl_ntfset_xxx
```

### 3. Add config to `config/runtime.exs`

```elixir
config :paddle_billing, :config,
  environment: System.get_env("PADDLE_BILLING_ENVIRONMENT", "sandbox"),
  api_key: System.get_env("PADDLE_BILLING_API_KEY"),
  client_token: System.get_env("PADDLE_BILLING_CLIENT_TOKEN"),
  signing_secret: System.get_env("PADDLE_BILLING_SIGNING_SECRET")
```

### 4. Create Ecto schemas and migration

Copy the integration layer to your project:

```
lib/your_app/billing.ex              # Context (public API)
lib/your_app/billing/paddle_product.ex
lib/your_app/billing/paddle_price.ex
lib/your_app/billing/paddle_discount.ex
lib/your_app/billing/sync.ex
```

Copy and run the migration:

```bash
mix ecto.migrate
```

### 5. Set up webhooks

Copy the webhook controller and plug:

```
lib/your_app_web/controllers/paddle_webhook_controller.ex
lib/your_app_web/plugs/paddle_webhook_signature.ex
```

Add the webhook route to your `router.ex`:

```elixir
scope "/webhooks", YourAppWeb do
  pipe_through :paddle_webhook
  post "/paddle", PaddleWebhookController, :handle
end
```

Add the raw body caching to `endpoint.ex` for the webhook path.

### 6. Install admin panel (optional)

```bash
mix paddle_billing.install
```

Options:

```bash
mix paddle_billing.install --web-module MyAppWeb --context-module MyApp.Billing
mix paddle_billing.install --no-routes  # skip route injection, print instructions
```

The installer:
- Copies LiveViews to `lib/your_app_web/live/paddle/`
- Copies components to `lib/your_app_web/components/paddle_components.ex`
- Copies Paddle.js hook to `assets/js/hooks/paddle_checkout.js`
- Injects routes into `router.ex`

After installing, register the JS hook in `assets/js/hooks/index.js`:

```javascript
import PaddleCheckout from "./paddle_checkout"

export default {
  // ...existing hooks
  PaddleCheckout,
}
```

### 7. Set up auto-sync (optional)

Copy the Oban worker:

```
lib/your_app/workers/paddle_sync_worker.ex
```

Add to Oban crontab in `config/config.exs`:

```elixir
config :your_app, Oban,
  queues: [default: 10],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 */6 * * *", YourApp.Workers.PaddleSyncWorker}
     ]}
  ]
```

## Usage

### API Client (direct)

```elixir
# List products from Paddle API
{:ok, products} = PaddleBilling.Products.list_all()

# Create a product
{:ok, product} = PaddleBilling.Products.create(%{
  "name" => "Pro Plan",
  "tax_category" => "standard"
})

# Get a price
{:ok, price} = PaddleBilling.Prices.get("pri_01h...")
```

### Billing Context (dual-write)

All operations write to Paddle API and local database atomically:

```elixir
alias YourApp.Billing

# Create product (Paddle + local DB)
{:ok, product} = Billing.create_product(%{
  "name" => "Pro Plan",
  "tax_category" => "standard",
  "plan_level" => "starter",
  "app_role" => "subscription"
})

# Create price for product
{:ok, price} = Billing.create_price(product, %{
  "amount" => 2900,           # in cents ($29.00)
  "currency_code" => "USD",
  "billing_cycle_interval" => "month",
  "billing_cycle_frequency" => 1,
  "description" => "Monthly Pro"
})

# Update product
{:ok, updated} = Billing.update_product(product, %{"name" => "Pro Plan v2"})

# Archive
{:ok, archived} = Billing.archive_product(product)

# List from local DB (fast, no API call)
products = Billing.list_products(status: "active", app_role: :subscription)
prices = Billing.list_prices_for_product(product.paddle_id)
discounts = Billing.list_discounts(status: "active")
```

### Sync

```elixir
# Pull everything from Paddle -> local DB
{:ok, results} = Billing.sync_all_from_paddle()

# Pull one resource type
{:ok, products} = Billing.sync_from_paddle(:products)
{:ok, prices} = Billing.sync_from_paddle(:prices)
{:ok, discounts} = Billing.sync_from_paddle(:discounts)

# Detect drift (compare local checksums vs Paddle API)
{:ok, drift} = Billing.detect_drift(:products)
# => [{%PaddleProduct{}, :in_sync}, {%PaddleProduct{}, :drifted}, ...]

# Reconcile with strategy
{:ok, results} = Billing.reconcile(:products, strategy: :paddle_wins)   # Paddle overwrites local
{:ok, results} = Billing.reconcile(:products, strategy: :local_wins)    # Local pushes to Paddle
{:ok, results} = Billing.reconcile(:products, strategy: :newest_wins)   # Newer timestamp wins
```

### Checkout

```elixir
# Create a checkout session (Paddle Transaction)
{:ok, transaction_id} = Billing.create_checkout(
  ["pri_01h..."],                          # price IDs
  custom_data: %{"account_id" => 123}      # passed to webhooks
)

# Preview pricing without creating a transaction
{:ok, preview} = Billing.preview_checkout(
  ["pri_01h..."],
  currency_code: "EUR",
  discount_id: "dsc_01h..."
)

# Get params for Paddle.js frontend
params = Billing.checkout_params(["pri_01h..."],
  success_url: "https://example.com/success",
  display_mode: "overlay"
)

# Get client token and environment for frontend
Billing.client_token()   # => "test_xxx"
Billing.environment()    # => :sandbox
```

Frontend checkout route: `/checkout?price_id=pri_01h...` or `/checkout?price_ids=pri_01h...,pri_02h...`

### Webhook verification

```elixir
# Verify webhook signature manually
:ok = PaddleBilling.Webhook.Verifier.verify(
  raw_body,
  paddle_signature_header,
  signing_secret,
  max_age: 300
)
```

The webhook controller handles this automatically via the `PaddleWebhookSignature` plug.

## Admin Panel

After running `mix paddle_billing.install`, the following routes are available:

| Route | Description |
|-------|-------------|
| `/admin/billing` | Products list |
| `/admin/billing/products/new` | Create product |
| `/admin/billing/products/:id/edit` | Edit product |
| `/admin/billing/products/:id/prices` | Prices for product |
| `/admin/billing/products/:id/prices/new` | Create price |
| `/admin/billing/discounts` | Discounts list |
| `/admin/billing/discounts/new` | Create discount |
| `/admin/billing/sync` | Sync dashboard (drift detection, reconciliation) |
| `/checkout` | Paddle.js checkout (authenticated users) |

Admin routes require the `:require_admin` LiveAuth on_mount hook.

## Library Structure

```
lib/
  paddle_billing.ex              # Public facade with delegates
  paddle_billing/
    config.ex                    # Env-based configuration
    client.ex                    # Req HTTP client + pagination + rate limits
    error.ex                     # Error structs
    resources/
      product.ex                 # Products CRUD
      price.ex                   # Prices CRUD
      discount.ex                # Discounts CRUD
      transaction.ex             # Transactions CRUD + preview
    webhook/
      verifier.ex                # HMAC-SHA256 + replay protection

priv/templates/                  # Installable admin panel templates
  components/
    paddle_components.ex         # Shared function components
  live/paddle/
    products_live.ex             # Products management
    prices_live.ex               # Prices management
    discounts_live.ex            # Discounts management
    sync_live.ex                 # Sync dashboard
    checkout_live.ex             # Paddle.js checkout
  js/
    paddle_checkout.js           # LiveView JS hook for Paddle.js

lib/mix/tasks/
  paddle_billing.install.ex      # Mix task installer
```

## Paddle API v2 Reference

- Base URL (sandbox): `https://sandbox-api.paddle.com`
- Base URL (production): `https://api.paddle.com`
- Auth: `Authorization: Bearer {api_key}`
- Pagination: cursor-based (`meta.pagination.next`, `meta.pagination.has_more`)
- Amounts: strings in smallest unit (e.g. `"2900"` = $29.00)
- Webhook signature: `Paddle-Signature: ts=TIMESTAMP;h1=HMAC_SHA256`
