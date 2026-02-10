defmodule PaddleBilling.Client do
  @moduledoc """
  HTTP client for the Paddle Billing API v2.

  Uses Req with Bearer token auth, JSON encoding, cursor-based pagination,
  and rate limit handling (429 + Retry-After).
  """

  alias PaddleBilling.{Config, Error}

  @max_retries 3
  @default_retry_delay 1_000

  @doc "GET request to a Paddle API path."
  def get(path, params \\ []) do
    request(:get, path, nil, params)
  end

  @doc "POST request to a Paddle API path."
  def post(path, body, params \\ []) do
    request(:post, path, body, params)
  end

  @doc "PATCH request to a Paddle API path."
  def patch(path, body, params \\ []) do
    request(:patch, path, body, params)
  end

  @doc "DELETE request to a Paddle API path."
  def delete(path, params \\ []) do
    request(:delete, path, nil, params)
  end

  @doc """
  Auto-paginate through all pages of a list endpoint.
  Returns {:ok, [items]} or {:error, Error.t()}.
  """
  def list_all(path, params \\ []) do
    list_all_recursive(path, params, [])
  end

  defp list_all_recursive(path, params, acc) do
    case get(path, params) do
      {:ok, %{"data" => data, "meta" => meta}} ->
        items = acc ++ data

        case get_in(meta, ["pagination", "has_more"]) do
          true ->
            next_cursor = get_in(meta, ["pagination", "next"])
            list_all_recursive(path, Keyword.put(params, :after, next_cursor), items)

          _ ->
            {:ok, items}
        end

      {:ok, %{"data" => data}} ->
        {:ok, acc ++ data}

      {:error, _} = error ->
        error
    end
  end

  defp request(method, path, body, params, retry_count \\ 0) do
    url = Config.base_url() <> path

    req_opts =
      [
        method: method,
        url: url,
        headers: [
          {"authorization", "Bearer #{Config.api_key()}"},
          {"content-type", "application/json"},
          {"accept", "application/json"}
        ],
        params: params,
        retry: false
      ]
      |> maybe_add_body(method, body)

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: response_body}}
      when status in 200..299 ->
        {:ok, response_body}

      {:ok, %Req.Response{status: 429, headers: headers}} ->
        retry_after = get_retry_after(headers)

        if retry_count < @max_retries do
          Process.sleep(retry_after * 1_000)
          request(method, path, body, params, retry_count + 1)
        else
          {:error, Error.rate_limited(retry_after)}
        end

      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:error, Error.from_response(response_body, status)}

      {:error, exception} ->
        {:error, Error.network_error(exception)}
    end
  end

  defp maybe_add_body(opts, method, body) when method in [:post, :patch] and not is_nil(body) do
    Keyword.put(opts, :body, Jason.encode!(body))
  end

  defp maybe_add_body(opts, _method, _body), do: opts

  defp get_retry_after(headers) do
    headers
    |> Enum.find_value(fn
      {"retry-after", value} -> String.to_integer(value)
      _ -> nil
    end)
    |> Kernel.||(@default_retry_delay)
  end
end
