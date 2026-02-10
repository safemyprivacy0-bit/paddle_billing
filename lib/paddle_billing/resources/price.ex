defmodule PaddleBilling.Prices do
  @moduledoc """
  CRUD operations for Paddle Prices.

  API docs: https://developer.paddle.com/api-reference/prices/overview
  """

  alias PaddleBilling.Client

  @path "/prices"

  @doc """
  List prices with optional filters.

  Options:
    - product_id: filter by product
    - status: "active" | "archived"
    - id: comma-separated list of price IDs
    - after: pagination cursor
    - per_page: items per page
  """
  def list(opts \\ []) do
    Client.get(@path, opts)
  end

  @doc "List all prices (auto-paginate)."
  def list_all(opts \\ []) do
    Client.list_all(@path, opts)
  end

  @doc "Get a single price by Paddle ID."
  def get(paddle_id) do
    case Client.get("#{@path}/#{paddle_id}") do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, _} = error -> error
    end
  end

  @doc """
  Create a price.

  Required attrs: product_id, description, unit_price (%{amount, currency_code}),
                  billing_cycle (optional, %{interval, frequency})
  """
  def create(attrs) when is_map(attrs) do
    case Client.post(@path, attrs) do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, _} = error -> error
    end
  end

  @doc "Update a price. Accepts partial attrs."
  def update(paddle_id, attrs) when is_map(attrs) do
    case Client.patch("#{@path}/#{paddle_id}", attrs) do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, _} = error -> error
    end
  end
end
