defmodule RawrPhoenixWeb.Paddle.CheckoutLive do
  @moduledoc "LiveView for Paddle checkout - creates a transaction and opens Paddle.js."
  use RawrPhoenixWeb, :live_view

  alias RawrPhoenix.Billing

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Checkout",
       transaction_id: nil,
       checkout_status: :idle,
       error: nil,
       items: [],
       display_mode: "overlay"
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    price_ids = parse_price_ids(params)
    display_mode = params["display_mode"] || "overlay"

    socket = assign(socket, items: price_ids, display_mode: display_mode)

    if connected?(socket) and price_ids != [] do
      case create_checkout_transaction(socket, price_ids, params) do
        {:ok, transaction_id} ->
          {:noreply, assign(socket, transaction_id: transaction_id, checkout_status: :ready)}

        {:error, error} ->
          {:noreply, assign(socket, error: inspect(error), checkout_status: :error)}
      end
    else
      {:noreply, socket}
    end
  end

  # ── Paddle.js events ──────────────────────────────────────────

  @impl true
  def handle_event("paddle-checkout-completed", params, socket) do
    {:noreply,
     assign(socket, checkout_status: :completed, transaction_id: params["transaction_id"])}
  end

  def handle_event("paddle-checkout-closed", _params, socket) do
    {:noreply, assign(socket, checkout_status: :closed)}
  end

  def handle_event("paddle-checkout-error", %{"error" => error}, socket) do
    {:noreply, assign(socket, checkout_status: :error, error: error)}
  end

  def handle_event("paddle-checkout-loaded", _params, socket) do
    {:noreply, assign(socket, checkout_status: :active)}
  end

  def handle_event("paddle-checkout-customer-created", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("paddle-checkout-payment-selected", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("retry", _params, socket) do
    case create_checkout_transaction(socket, socket.assigns.items, %{}) do
      {:ok, transaction_id} ->
        {:noreply,
         assign(socket,
           transaction_id: transaction_id,
           checkout_status: :ready,
           error: nil
         )}

      {:error, error} ->
        {:noreply, assign(socket, error: inspect(error), checkout_status: :error)}
    end
  end

  # ── Render ────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <.loading_state :if={@checkout_status == :idle and @items != []} />
      <.empty_state :if={@items == []} />

      <div
        :if={@transaction_id && @checkout_status in [:ready, :active]}
        id="paddle-checkout"
        phx-hook="PaddleCheckout"
        data-transaction-id={@transaction_id}
        data-environment={Billing.environment()}
        data-client-token={Billing.client_token()}
        data-display-mode={@display_mode}
        data-theme="light"
      >
        <div
          :if={@display_mode == "inline"}
          id="paddle-checkout-container"
          data-paddle-checkout-container
          class="min-h-[450px]"
        >
        </div>
      </div>

      <.completed_state :if={@checkout_status == :completed} />
      <.closed_state :if={@checkout_status == :closed} />
      <.error_state :if={@checkout_status == :error} error={@error} />
    </div>
    """
  end

  # ── Components ────────────────────────────────────────────────

  defp loading_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <span class="loading loading-spinner loading-lg text-primary"></span>
      <p class="mt-4 text-base-content/60">Preparing checkout...</p>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <.icon name="hero-shopping-cart" class="w-16 h-16 mx-auto text-base-content/30" />
      <h2 class="mt-4 text-xl font-semibold">No items selected</h2>
      <p class="mt-2 text-base-content/60">Add items to your cart to proceed with checkout.</p>
      <.link navigate="/pricing" class="btn btn-primary mt-6">View Pricing</.link>
    </div>
    """
  end

  defp completed_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <div class="w-16 h-16 mx-auto bg-success/20 rounded-full flex items-center justify-center">
        <.icon name="hero-check" class="w-8 h-8 text-success" />
      </div>
      <h2 class="mt-4 text-xl font-semibold">Payment successful!</h2>
      <p class="mt-2 text-base-content/60">
        Thank you for your purchase. You'll receive a confirmation email shortly.
      </p>
      <.link navigate="/" class="btn btn-primary mt-6">Go to Dashboard</.link>
    </div>
    """
  end

  defp closed_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <.icon name="hero-x-circle" class="w-16 h-16 mx-auto text-base-content/30" />
      <h2 class="mt-4 text-xl font-semibold">Checkout cancelled</h2>
      <p class="mt-2 text-base-content/60">You can try again or go back to pricing.</p>
      <div class="mt-6 flex gap-3 justify-center">
        <button phx-click="retry" class="btn btn-primary">Try Again</button>
        <.link navigate="/pricing" class="btn btn-ghost">View Pricing</.link>
      </div>
    </div>
    """
  end

  defp error_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <div class="w-16 h-16 mx-auto bg-error/20 rounded-full flex items-center justify-center">
        <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-error" />
      </div>
      <h2 class="mt-4 text-xl font-semibold">Something went wrong</h2>
      <p :if={@error} class="mt-2 text-error text-sm"><%= @error %></p>
      <div class="mt-6 flex gap-3 justify-center">
        <button phx-click="retry" class="btn btn-primary">Retry</button>
        <.link navigate="/pricing" class="btn btn-ghost">Go Back</.link>
      </div>
    </div>
    """
  end

  # ── Private ──────────────────────────────────────────────────

  defp create_checkout_transaction(socket, price_ids, params) do
    custom_data = %{}

    custom_data =
      if socket.assigns[:current_identity] do
        Map.put(custom_data, "identity_id", socket.assigns.current_identity.id)
      else
        custom_data
      end

    custom_data =
      if socket.assigns[:current_account] do
        Map.put(custom_data, "account_id", socket.assigns.current_account.id)
      else
        custom_data
      end

    custom_data =
      case params["custom_data"] do
        nil -> custom_data
        extra when is_map(extra) -> Map.merge(custom_data, extra)
        _ -> custom_data
      end

    Billing.create_checkout(price_ids, custom_data: custom_data)
  end

  defp parse_price_ids(params) do
    cond do
      params["price_id"] ->
        [params["price_id"]]

      params["price_ids"] ->
        params["price_ids"]
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      true ->
        []
    end
  end
end
