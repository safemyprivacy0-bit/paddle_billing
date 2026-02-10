defmodule RawrPhoenixWeb.Components.PaddleComponents do
  @moduledoc """
  Shared function components for the PaddleBilling admin panel.

  Provides badges, formatted displays, and form helpers for
  products, prices, discounts, and sync status.
  """
  use Phoenix.Component

  import RawrPhoenixWeb.CoreComponents, only: [icon: 1]

  # ── Status Badges ──────────────────────────────────────────────────

  @doc "Colored badge for product/price/discount status."
  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      status_badge_class(@status)
    ]}>
      {@status}
    </span>
    """
  end

  defp status_badge_class("active"), do: "badge-success"
  defp status_badge_class("archived"), do: "badge-ghost"
  defp status_badge_class("syncing"), do: "badge-warning"
  defp status_badge_class(_), do: "badge-ghost"

  # ── Price Display ──────────────────────────────────────────────────

  @doc "Formatted price with currency and billing cycle."
  attr :price, :map, required: true

  def price_display(assigns) do
    ~H"""
    <span class="font-mono">
      {format_amount(@price.amount, @price.currency_code)}
    </span>
    <span :if={@price.billing_cycle_interval} class="text-sm text-base-content/60">
      / {cycle_label(@price.billing_cycle_interval, @price.billing_cycle_frequency)}
    </span>
    <span :if={!@price.billing_cycle_interval} class="text-sm text-base-content/60">
      one-time
    </span>
    """
  end

  # ── Discount Badge ─────────────────────────────────────────────────

  @doc "Display badge for a discount amount."
  attr :discount, :map, required: true

  def discount_badge(assigns) do
    ~H"""
    <span class="badge badge-info badge-sm font-mono">
      {format_discount(@discount)}
    </span>
    """
  end

  # ── Sync Status ────────────────────────────────────────────────────

  @doc "Icon + text for sync state."
  attr :synced_at, :any, default: nil

  def sync_status(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5 text-sm">
      <span :if={@synced_at} class="text-success">
        <.icon name="hero-check-circle-mini" class="size-4" />
      </span>
      <span :if={!@synced_at} class="text-warning">
        <.icon name="hero-exclamation-circle-mini" class="size-4" />
      </span>
      <span class="text-base-content/60">
        {if @synced_at, do: format_relative(@synced_at), else: "Never synced"}
      </span>
    </div>
    """
  end

  # ── Drift Indicator ────────────────────────────────────────────────

  @doc "Visual indicator for drift status."
  attr :status, :atom, required: true

  def drift_indicator(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-1.5 text-sm font-medium",
      drift_color(@status)
    ]}>
      <span class={["size-2 rounded-full", drift_dot(@status)]}></span>
      {drift_label(@status)}
    </div>
    """
  end

  defp drift_color(:in_sync), do: "text-success"
  defp drift_color(:drifted), do: "text-warning"
  defp drift_color(:local_only), do: "text-info"
  defp drift_color(:paddle_only), do: "text-error"
  defp drift_color(_), do: "text-base-content/60"

  defp drift_dot(:in_sync), do: "bg-success"
  defp drift_dot(:drifted), do: "bg-warning"
  defp drift_dot(:local_only), do: "bg-info"
  defp drift_dot(:paddle_only), do: "bg-error"
  defp drift_dot(_), do: "bg-base-content/30"

  defp drift_label(:in_sync), do: "In Sync"
  defp drift_label(:drifted), do: "Drifted"
  defp drift_label(:local_only), do: "Local Only"
  defp drift_label(:paddle_only), do: "Paddle Only"
  defp drift_label(_), do: "Unknown"

  # ── Helpers ────────────────────────────────────────────────────────

  defp format_amount(nil, _currency), do: "--"

  defp format_amount(amount, currency) when is_integer(amount) do
    dollars = div(amount, 100)
    cents = rem(amount, 100)
    symbol = currency_symbol(currency)
    "#{symbol}#{dollars}.#{String.pad_leading("#{cents}", 2, "0")}"
  end

  defp format_amount(amount, _currency), do: to_string(amount)

  defp currency_symbol("USD"), do: "$"
  defp currency_symbol("EUR"), do: "€"
  defp currency_symbol("GBP"), do: "£"
  defp currency_symbol("PLN"), do: "zł"
  defp currency_symbol(nil), do: "$"
  defp currency_symbol(code), do: "#{code} "

  defp cycle_label(interval, 1), do: interval
  defp cycle_label(interval, freq), do: "#{freq} #{interval}s"

  defp format_discount(%{type: "percentage", amount: amount}), do: "#{amount}%"
  defp format_discount(%{type: "flat", amount: amount, currency_code: cur}), do: format_amount(parse_int(amount), cur)
  defp format_discount(%{type: "flat_per_seat", amount: amount, currency_code: cur}), do: "#{format_amount(parse_int(amount), cur)}/seat"
  defp format_discount(%{amount: amount}), do: to_string(amount)

  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)
  defp parse_int(_), do: 0

  defp format_relative(nil), do: "Never"

  defp format_relative(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp format_relative(_), do: "Unknown"
end
