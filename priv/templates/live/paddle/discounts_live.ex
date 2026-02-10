defmodule RawrPhoenixWeb.Paddle.DiscountsLive do
  @moduledoc "Admin LiveView for managing Paddle discounts."
  use RawrPhoenixWeb, :live_view

  alias RawrPhoenix.Billing
  alias RawrPhoenix.Billing.PaddleDiscount

  import RawrPhoenixWeb.Components.PaddleComponents

  @discount_types [{"Percentage", "percentage"}, {"Flat", "flat"}, {"Flat per seat", "flat_per_seat"}]
  @currencies ~w(USD EUR GBP PLN)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Billing - Discounts")
     |> assign(:discounts, Billing.list_discounts())
     |> assign(:discount_types, @discount_types)
     |> assign(:currencies, @currencies)
     |> assign(:prices, Billing.list_prices())}
  end

  @impl true
  def handle_params(%{"paddle_id" => paddle_id}, _uri, %{assigns: %{live_action: :edit}} = socket) do
    {:noreply, assign(socket, :discount, Billing.get_discount!(paddle_id))}
  end

  def handle_params(_params, _uri, socket) do
    case socket.assigns.live_action do
      :index ->
        {:noreply, assign(socket, :discount, nil)}

      :new ->
        {:noreply,
         assign(socket, :discount, %PaddleDiscount{
           status: "active",
           type: "percentage",
           enabled_for_checkout: true,
           recur: false
         })}
    end
  end

  @impl true
  def handle_event("save", %{"discount" => params}, socket) do
    case socket.assigns.live_action do
      :new -> create_discount(socket, params)
      :edit -> update_discount(socket, params)
    end
  end

  def handle_event("sync", _params, socket) do
    case Billing.sync_from_paddle(:discounts) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:discounts, Billing.list_discounts())
         |> put_flash(:info, "Discounts synced from Paddle.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Sync failed: #{inspect(reason)}")}
    end
  end

  defp create_discount(socket, params) do
    params = normalize_discount_params(params)

    case Billing.create_discount(params) do
      {:ok, _discount} ->
        {:noreply,
         socket
         |> assign(:discounts, Billing.list_discounts())
         |> put_flash(:info, "Discount created.")
         |> push_patch(to: ~p"/admin/billing/discounts")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  defp update_discount(socket, params) do
    discount = socket.assigns.discount
    params = normalize_discount_params(params)

    case Billing.update_discount(discount, params) do
      {:ok, _discount} ->
        {:noreply,
         socket
         |> assign(:discounts, Billing.list_discounts())
         |> put_flash(:info, "Discount updated.")
         |> push_patch(to: ~p"/admin/billing/discounts")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  defp normalize_discount_params(params) do
    params
    |> Map.put("enabled_for_checkout", params["enabled_for_checkout"] == "true")
    |> Map.put("recur", params["recur"] == "true")
    |> maybe_parse_int("usage_limit")
    |> maybe_parse_int("max_recurring_intervals")
    |> normalize_restrict_to()
  end

  defp maybe_parse_int(params, key) do
    case params[key] do
      nil -> params
      "" -> Map.put(params, key, nil)
      val -> Map.put(params, key, String.to_integer(val))
    end
  end

  defp normalize_restrict_to(%{"restrict_to" => val} = params) when is_binary(val) do
    ids =
      val
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Map.put(params, "restrict_to", if(ids == [], do: nil, else: ids))
  end

  defp normalize_restrict_to(params), do: params

  @impl true
  def render(assigns) do
    ~H"""
    <.page_container>
      <.discounts_header />
      <.discount_form
        :if={@live_action in [:new, :edit]}
        discount={@discount}
        action={@live_action}
        discount_types={@discount_types}
        currencies={@currencies}
        prices={@prices}
      />
      <.discounts_table :if={@live_action == :index} discounts={@discounts} />
    </.page_container>
    """
  end

  # ── Function Components ─────────────────────────────────────────

  defp discounts_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-2xl font-bold">Billing - Discounts</h1>
        <div class="flex gap-2 mt-2">
          <.link navigate={~p"/admin/billing"} class="btn btn-sm btn-ghost">Products</.link>
          <.link navigate={~p"/admin/billing/discounts"} class="btn btn-sm btn-primary btn-soft">Discounts</.link>
          <.link navigate={~p"/admin/billing/sync"} class="btn btn-sm btn-ghost">Sync</.link>
        </div>
      </div>
      <div class="flex gap-2">
        <button phx-click="sync" class="btn btn-sm btn-outline">Sync from Paddle</button>
        <.link navigate={~p"/admin/billing/discounts/new"} class="btn btn-sm btn-primary">
          New Discount
        </.link>
      </div>
    </div>
    """
  end

  defp discounts_table(assigns) do
    ~H"""
    <div :if={@discounts == []} class="text-center py-12 text-base-content/50">
      No discounts yet. Create one or sync from Paddle.
    </div>

    <div :if={@discounts != []} class="overflow-x-auto">
      <table class="table w-full">
        <thead>
          <tr>
            <th>Code</th>
            <th>Description</th>
            <th>Type / Amount</th>
            <th>Status</th>
            <th>Usage</th>
            <th>Expires</th>
            <th>Checkout</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <.discount_row :for={discount <- @discounts} discount={discount} />
        </tbody>
      </table>
    </div>
    """
  end

  defp discount_row(assigns) do
    ~H"""
    <tr>
      <td>
        <span :if={@discount.code} class="font-mono text-sm badge badge-ghost">
          {@discount.code}
        </span>
        <span :if={!@discount.code} class="text-sm text-base-content/50">--</span>
      </td>
      <td class="text-sm max-w-xs truncate">{@discount.description || "--"}</td>
      <td><.discount_badge discount={@discount} /></td>
      <td><.status_badge status={@discount.status} /></td>
      <td class="text-sm">
        {@discount.times_used || 0}
        <span :if={@discount.usage_limit} class="text-base-content/50">/ {@discount.usage_limit}</span>
      </td>
      <td class="text-sm">
        {if @discount.expires_at, do: Calendar.strftime(@discount.expires_at, "%Y-%m-%d"), else: "Never"}
      </td>
      <td>
        <span :if={@discount.enabled_for_checkout} class="badge badge-success badge-xs">Yes</span>
        <span :if={!@discount.enabled_for_checkout} class="badge badge-ghost badge-xs">No</span>
      </td>
      <td>
        <.link
          navigate={~p"/admin/billing/discounts/#{@discount.paddle_id}/edit"}
          class="btn btn-xs btn-ghost"
        >
          Edit
        </.link>
      </td>
    </tr>
    """
  end

  defp discount_form(assigns) do
    ~H"""
    <.card class="mb-6">
      <div class="card-body p-5">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold">
            {if @action == :new, do: "New Discount", else: "Edit Discount"}
          </h2>
          <.link navigate={~p"/admin/billing/discounts"} class="btn btn-sm btn-ghost">Cancel</.link>
        </div>

        <form novalidate phx-submit="save" class="space-y-4">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Description</span></label>
              <input
                type="text"
                name="discount[description]"
                value={@discount.description}
                class="input input-bordered w-full"
              />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Code</span></label>
              <input
                type="text"
                name="discount[code]"
                value={@discount.code}
                class="input input-bordered w-full font-mono"
                placeholder="SAVE20"
              />
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Type</span></label>
              <select name="discount[type]" class="select select-bordered w-full">
                <option
                  :for={{label, val} <- @discount_types}
                  value={val}
                  selected={@discount.type == val}
                >
                  {label}
                </option>
              </select>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Amount</span></label>
              <input
                type="text"
                name="discount[amount]"
                value={@discount.amount}
                class="input input-bordered w-full font-mono"
                placeholder="e.g. 20 for 20%"
                required
              />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Currency (for flat)</span></label>
              <select name="discount[currency_code]" class="select select-bordered w-full">
                <option value="">N/A (percentage)</option>
                <option
                  :for={cur <- @currencies}
                  value={cur}
                  selected={@discount.currency_code == cur}
                >
                  {cur}
                </option>
              </select>
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div class="form-control">
              <label class="label cursor-pointer justify-start gap-3">
                <input
                  type="checkbox"
                  name="discount[recur]"
                  value="true"
                  checked={@discount.recur}
                  class="checkbox checkbox-sm"
                />
                <span class="label-text">Recurring</span>
              </label>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Max Recurring Intervals</span></label>
              <input
                type="number"
                name="discount[max_recurring_intervals]"
                value={@discount.max_recurring_intervals}
                min="1"
                class="input input-bordered w-full"
              />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Usage Limit</span></label>
              <input
                type="number"
                name="discount[usage_limit]"
                value={@discount.usage_limit}
                min="1"
                class="input input-bordered w-full"
              />
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Expires At</span></label>
              <input
                type="datetime-local"
                name="discount[expires_at]"
                value={format_datetime_local(@discount.expires_at)}
                class="input input-bordered w-full"
              />
            </div>

            <div class="form-control">
              <label class="label cursor-pointer justify-start gap-3">
                <input
                  type="checkbox"
                  name="discount[enabled_for_checkout]"
                  value="true"
                  checked={@discount.enabled_for_checkout}
                  class="checkbox checkbox-sm"
                />
                <span class="label-text">Enabled for Checkout</span>
              </label>
            </div>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text">Restrict to Price IDs (comma-separated)</span></label>
            <input
              type="text"
              name="discount[restrict_to]"
              value={if @discount.restrict_to, do: Enum.join(@discount.restrict_to, ", "), else: ""}
              class="input input-bordered w-full font-mono text-sm"
              placeholder="pri_abc123, pri_def456"
            />
          </div>

          <div class="flex justify-end pt-2">
            <button type="submit" class="btn btn-primary">
              {if @action == :new, do: "Create Discount", else: "Update Discount"}
            </button>
          </div>
        </form>
      </div>
    </.card>
    """
  end

  defp format_datetime_local(nil), do: nil

  defp format_datetime_local(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
  end

  defp format_datetime_local(_), do: nil
end
