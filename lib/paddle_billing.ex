defmodule PaddleBilling do
  @moduledoc """
  Public facade for the PaddleBilling library.

  Delegates to resource-specific modules for Products, Prices, and Discounts.
  This library is fully portable - zero imports from RawrPhoenix.*.
  """

  # ── Products ──────────────────────────────────────────────────────

  defdelegate list_products(opts \\ []), to: PaddleBilling.Products, as: :list
  defdelegate list_all_products(opts \\ []), to: PaddleBilling.Products, as: :list_all
  defdelegate get_product(paddle_id), to: PaddleBilling.Products, as: :get
  defdelegate create_product(attrs), to: PaddleBilling.Products, as: :create
  defdelegate update_product(paddle_id, attrs), to: PaddleBilling.Products, as: :update

  # ── Prices ────────────────────────────────────────────────────────

  defdelegate list_prices(opts \\ []), to: PaddleBilling.Prices, as: :list
  defdelegate list_all_prices(opts \\ []), to: PaddleBilling.Prices, as: :list_all
  defdelegate get_price(paddle_id), to: PaddleBilling.Prices, as: :get
  defdelegate create_price(attrs), to: PaddleBilling.Prices, as: :create
  defdelegate update_price(paddle_id, attrs), to: PaddleBilling.Prices, as: :update

  # ── Discounts ─────────────────────────────────────────────────────

  defdelegate list_discounts(opts \\ []), to: PaddleBilling.Discounts, as: :list
  defdelegate list_all_discounts(opts \\ []), to: PaddleBilling.Discounts, as: :list_all
  defdelegate get_discount(paddle_id), to: PaddleBilling.Discounts, as: :get
  defdelegate create_discount(attrs), to: PaddleBilling.Discounts, as: :create
  defdelegate update_discount(paddle_id, attrs), to: PaddleBilling.Discounts, as: :update

  # ── Transactions ─────────────────────────────────────────────────

  defdelegate list_transactions(opts \\ []), to: PaddleBilling.Transactions, as: :list
  defdelegate list_all_transactions(opts \\ []), to: PaddleBilling.Transactions, as: :list_all
  defdelegate get_transaction(paddle_id), to: PaddleBilling.Transactions, as: :get
  defdelegate create_transaction(attrs), to: PaddleBilling.Transactions, as: :create
  defdelegate update_transaction(paddle_id, attrs), to: PaddleBilling.Transactions, as: :update
  defdelegate preview_transaction(attrs), to: PaddleBilling.Transactions, as: :preview

  # ── Config ────────────────────────────────────────────────────────

  defdelegate client_token(), to: PaddleBilling.Config
  defdelegate environment(), to: PaddleBilling.Config
end
