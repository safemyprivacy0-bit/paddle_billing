defmodule PaddleBilling.Products do
  @moduledoc """
  CRUD operations for Paddle Products.

  API docs: https://developer.paddle.com/api-reference/products/overview
  """

  alias PaddleBilling.Client

  @path "/products"

  @doc """
  List products with optional filters.

  Options:
    - status: "active" | "archived"
    - id: comma-separated list of product IDs
    - after: pagination cursor
    - per_page: items per page (max 200)
  """
  def list(opts \\ []) do
    Client.get(@path, opts)
  end

  @doc "List all products (auto-paginate)."
  def list_all(opts \\ []) do
    Client.list_all(@path, opts)
  end

  @doc "Get a single product by Paddle ID."
  def get(paddle_id) do
    case Client.get("#{@path}/#{paddle_id}") do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, _} = error -> error
    end
  end

  @doc """
  Create a product.

  Required attrs: name, tax_category
  Optional: description, image_url, custom_data
  """
  def create(attrs) when is_map(attrs) do
    case Client.post(@path, attrs) do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, _} = error -> error
    end
  end

  @doc """
  Update a product.

  Accepts partial attrs: name, description, tax_category, image_url, custom_data, status
  """
  def update(paddle_id, attrs) when is_map(attrs) do
    case Client.patch("#{@path}/#{paddle_id}", attrs) do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:error, _} = error -> error
    end
  end
end
