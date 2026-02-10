defmodule PaddleBilling.Discounts do
  @moduledoc """
  CRUD operations for Paddle Discounts.

  API docs: https://developer.paddle.com/api-reference/discounts/overview
  """

  alias PaddleBilling.Client

  @path "/discounts"

  @doc """
  List discounts with optional filters.

  Options:
    - status: "active" | "archived" | "expired" | "used"
    - code: filter by discount code
    - id: comma-separated list of discount IDs
    - after: pagination cursor
    - per_page: items per page
  """
  def list(opts \\ []) do
    Client.get(@path, opts)
  end

  @doc "List all discounts (auto-paginate)."
  def list_all(opts \\ []) do
    Client.list_all(@path, opts)
  end

  @doc "Get a single discount by Paddle ID."
  def get(paddle_id) do
    case Client.get("#{@path}/#{paddle_id}") do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, _} = error -> error
    end
  end

  @doc """
  Create a discount.

  Required attrs: amount, description, type
  Optional: currency_code, code, recur, max_recurring_intervals, usage_limit,
            restrict_to, expires_at, enabled_for_checkout, custom_data
  """
  def create(attrs) when is_map(attrs) do
    case Client.post(@path, attrs) do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, _} = error -> error
    end
  end

  @doc "Update a discount. Accepts partial attrs."
  def update(paddle_id, attrs) when is_map(attrs) do
    case Client.patch("#{@path}/#{paddle_id}", attrs) do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, _} = error -> error
    end
  end
end
