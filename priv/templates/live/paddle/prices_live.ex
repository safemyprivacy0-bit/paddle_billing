defmodule RawrPhoenixWeb.Paddle.PricesLive do
  @moduledoc "Admin LiveView for managing Paddle prices per product."
  use RawrPhoenixWeb, :live_view

  alias RawrPhoenix.Billing
  alias RawrPhoenix.Billing.PaddlePrice

  import RawrPhoenixWeb.Components.PaddleComponents

  @intervals [{"One-time", ""}, {"Month", "month"}, {"Year", "year"}, {"Week", "week"}, {"Day", "day"}]
  @tax_modes ~w(account_setting internal external)
  @currencies ~w(USD EUR GBP PLN)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Billing - Prices")
     |> assign(:intervals, @intervals)
     |> assign(:tax_modes, @tax_modes)
     |> assign(:currencies, @currencies)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    paddle_id = params["paddle_id"]
    product = Billing.get_product!(paddle_id)
    prices = Billing.list_prices_for_product(paddle_id)

    socket =
      socket
      |> assign(:product, product)
      |> assign(:prices, prices)
      |> apply_price_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  defp apply_price_action(socket, :index, _params) do
    assign(socket, :price, nil)
  end

  defp apply_price_action(socket, :new, _params) do
    assign(socket, :price, %PaddlePrice{status: "active", currency_code: "USD", billing_cycle_frequency: 1})
  end

  defp apply_price_action(socket, :edit, %{"price_paddle_id" => price_id}) do
    assign(socket, :price, Billing.get_price!(price_id))
  end

  @impl true
  def handle_event("save", %{"price" => params}, socket) do
    params = normalize_price_params(params)

    case socket.assigns.live_action do
      :new -> create_price(socket, params)
      :edit -> update_price(socket, params)
    end
  end

  def handle_event("archive", %{"paddle-id" => paddle_id}, socket) do
    price = Billing.get_price!(paddle_id)

    case Billing.archive_price(price) do
      {:ok, _} ->
        {:noreply,
         socket
         |> reload_prices()
         |> put_flash(:info, "Price archived.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  defp create_price(socket, params) do
    product = socket.assigns.product

    case Billing.create_price(product, params) do
      {:ok, _price} ->
        {:noreply,
         socket
         |> reload_prices()
         |> put_flash(:info, "Price created.")
         |> push_patch(to: ~p"/admin/billing/products/#{product.paddle_id}/prices")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  defp update_price(socket, params) do
    price = socket.assigns.price
    product = socket.assigns.product

    case Billing.update_price(price, params) do
      {:ok, _price} ->
        {:noreply,
         socket
         |> reload_prices()
         |> put_flash(:info, "Price updated.")
         |> push_patch(to: ~p"/admin/billing/products/#{product.paddle_id}/prices")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  defp reload_prices(socket) do
    assign(socket, :prices, Billing.list_prices_for_product(socket.assigns.product.paddle_id))
  end

  defp normalize_price_params(params) do
    amount = params["amount"]

    amount_cents =
      case amount do
        nil -> nil
        "" -> nil
        val ->
          {dollars, _} = Float.parse(val)
          round(dollars * 100)
      end

    params
    |> Map.put("amount", amount_cents)
    |> Map.put("billing_cycle_interval", blank_to_nil(params["billing_cycle_interval"]))
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(val), do: val

  @impl true
  def render(assigns) do
    ~H"""
    <.page_container>
      <.prices_header product={@product} />
      <.price_form
        :if={@live_action in [:new, :edit]}
        price={@price}
        product={@product}
        action={@live_action}
        intervals={@intervals}
        tax_modes={@tax_modes}
        currencies={@currencies}
      />
      <.prices_table :if={@live_action == :index} prices={@prices} product={@product} />
    </.page_container>
    """
  end

  # ── Function Components ─────────────────────────────────────────

  defp prices_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <div>
        <div class="flex items-center gap-2 mb-1">
          <.link navigate={~p"/admin/billing"} class="text-sm text-base-content/50 hover:text-base-content">
            Products
          </.link>
          <span class="text-base-content/30">/</span>
          <span class="text-sm font-medium">{@product.name}</span>
        </div>
        <h1 class="text-2xl font-bold">Prices</h1>
      </div>
      <.link
        navigate={~p"/admin/billing/products/#{@product.paddle_id}/prices/new"}
        class="btn btn-sm btn-primary"
      >
        New Price
      </.link>
    </div>
    """
  end

  defp prices_table(assigns) do
    ~H"""
    <div :if={@prices == []} class="text-center py-12 text-base-content/50">
      No prices for this product yet.
    </div>

    <div :if={@prices != []} class="overflow-x-auto">
      <table class="table w-full">
        <thead>
          <tr>
            <th>Amount</th>
            <th>Billing Cycle</th>
            <th>Trial</th>
            <th>Status</th>
            <th>Tax Mode</th>
            <th>Synced</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <.price_row :for={price <- @prices} price={price} product={@product} />
        </tbody>
      </table>
    </div>
    """
  end

  defp price_row(assigns) do
    ~H"""
    <tr>
      <td><.price_display price={@price} /></td>
      <td>
        <span :if={@price.billing_cycle_interval} class="text-sm">
          Every {@price.billing_cycle_frequency} {@price.billing_cycle_interval}
        </span>
        <span :if={!@price.billing_cycle_interval} class="text-sm text-base-content/50">
          One-time
        </span>
      </td>
      <td>
        <span :if={@price.trial_interval} class="text-sm">
          {@price.trial_frequency} {@price.trial_interval}
        </span>
        <span :if={!@price.trial_interval} class="text-sm text-base-content/50">--</span>
      </td>
      <td><.status_badge status={@price.status} /></td>
      <td class="text-sm">{@price.tax_mode || "--"}</td>
      <td><.sync_status synced_at={@price.synced_at} /></td>
      <td>
        <div class="flex gap-1">
          <.link
            navigate={~p"/admin/billing/products/#{@product.paddle_id}/prices/#{@price.paddle_id}/edit"}
            class="btn btn-xs btn-ghost"
          >
            Edit
          </.link>
          <button
            :if={@price.status == "active"}
            phx-click="archive"
            phx-value-paddle-id={@price.paddle_id}
            data-confirm="Archive this price?"
            class="btn btn-xs btn-ghost text-error"
          >
            Archive
          </button>
        </div>
      </td>
    </tr>
    """
  end

  defp price_form(assigns) do
    assigns =
      assign(assigns, :amount_dollars,
        if(assigns.price.amount, do: assigns.price.amount / 100, else: nil)
      )

    ~H"""
    <.card class="mb-6">
      <div class="card-body p-5">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold">
            {if @action == :new, do: "New Price", else: "Edit Price"}
          </h2>
          <.link
            navigate={~p"/admin/billing/products/#{@product.paddle_id}/prices"}
            class="btn btn-sm btn-ghost"
          >
            Cancel
          </.link>
        </div>

        <form novalidate phx-submit="save" class="space-y-4">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Amount (major units, e.g. 29.00)</span></label>
              <input
                type="number"
                name="price[amount]"
                value={@amount_dollars}
                step="0.01"
                min="0"
                class="input input-bordered w-full"
                required
              />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Currency</span></label>
              <select name="price[currency_code]" class="select select-bordered w-full">
                <option
                  :for={cur <- @currencies}
                  value={cur}
                  selected={@price.currency_code == cur}
                >
                  {cur}
                </option>
              </select>
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Billing Cycle</span></label>
              <select name="price[billing_cycle_interval]" class="select select-bordered w-full">
                <option
                  :for={{label, val} <- @intervals}
                  value={val}
                  selected={@price.billing_cycle_interval == val || (@price.billing_cycle_interval == nil && val == "")}
                >
                  {label}
                </option>
              </select>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Billing Frequency</span></label>
              <input
                type="number"
                name="price[billing_cycle_frequency]"
                value={@price.billing_cycle_frequency || 1}
                min="1"
                class="input input-bordered w-full"
              />
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Trial Interval</span></label>
              <select name="price[trial_interval]" class="select select-bordered w-full">
                <option value="" selected={!@price.trial_interval}>None</option>
                <option value="day" selected={@price.trial_interval == "day"}>Day</option>
                <option value="week" selected={@price.trial_interval == "week"}>Week</option>
                <option value="month" selected={@price.trial_interval == "month"}>Month</option>
              </select>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Trial Frequency</span></label>
              <input
                type="number"
                name="price[trial_frequency]"
                value={@price.trial_frequency}
                min="1"
                class="input input-bordered w-full"
              />
            </div>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text">Tax Mode</span></label>
            <select name="price[tax_mode]" class="select select-bordered w-full">
              <option value="">Default</option>
              <option
                :for={mode <- @tax_modes}
                value={mode}
                selected={@price.tax_mode == mode}
              >
                {mode}
              </option>
            </select>
          </div>

          <div class="flex justify-end pt-2">
            <button type="submit" class="btn btn-primary">
              {if @action == :new, do: "Create Price", else: "Update Price"}
            </button>
          </div>
        </form>
      </div>
    </.card>
    """
  end
end
