defmodule PaddleBilling.Transactions do
  @moduledoc """
  CRUD operations for Paddle Transactions.

  Transactions represent checkout sessions / carts in Paddle.
  Create a transaction to get a transaction ID, then open Paddle.js checkout.

  API docs: https://developer.paddle.com/api-reference/transactions/overview
  """

  alias PaddleBilling.Client

  @path "/transactions"

  @doc """
  List transactions with optional filters.

  Options:
    - status: "draft" | "ready" | "billed" | "paid" | "completed" | "canceled" | "past_due"
    - id: comma-separated list of transaction IDs
    - customer_id: filter by customer
    - subscription_id: filter by subscription
    - invoice_number: filter by invoice number
    - after: pagination cursor
    - per_page: items per page (max 200)
  """
  def list(opts \\ []) do
    Client.get(@path, opts)
  end

  @doc "List all transactions (auto-paginate)."
  def list_all(opts \\ []) do
    Client.list_all(@path, opts)
  end

  @doc "Get a single transaction by Paddle ID."
  def get(paddle_id) do
    case Client.get("#{@path}/#{paddle_id}") do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, _} = error -> error
    end
  end

  @doc """
  Create a transaction (checkout cart).

  Required attrs: items (list of %{"price_id" => "pri_xxx", "quantity" => 1})
  Optional: customer_id, custom_data, discount_id, currency_code, collection_mode,
            billing_details, checkout
  """
  def create(attrs) when is_map(attrs) do
    case Client.post(@path, attrs) do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, _} = error -> error
    end
  end

  @doc """
  Update a transaction.

  Accepts partial attrs: items, status, custom_data, currency_code, etc.
  Only draft/ready transactions can be updated.
  """
  def update(paddle_id, attrs) when is_map(attrs) do
    case Client.patch("#{@path}/#{paddle_id}", attrs) do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, _} = error -> error
    end
  end

  @doc """
  Preview a transaction (get pricing without creating).

  Same attrs as create - returns calculated totals, tax, discounts.
  Useful for showing a price breakdown before checkout.
  """
  def preview(attrs) when is_map(attrs) do
    case Client.post("#{@path}/preview", attrs) do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, _} = error -> error
    end
  end
end
