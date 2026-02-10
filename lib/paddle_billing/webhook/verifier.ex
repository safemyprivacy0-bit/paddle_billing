defmodule PaddleBilling.Webhook.Verifier do
  @moduledoc """
  Verifies Paddle webhook signatures using HMAC-SHA256.

  Paddle-Signature header format: ts=TIMESTAMP;h1=HASH
  Signed payload: TIMESTAMP:RAW_BODY
  HMAC-SHA256 with signing_secret as key.

  Includes replay protection with configurable max age.
  """

  @default_max_age 300

  @doc """
  Verify a webhook signature.

  Returns `:ok` if valid, `{:error, reason}` if invalid.

  Options:
    - max_age: maximum age in seconds (default 300)
  """
  @spec verify(binary(), binary(), binary(), keyword()) :: :ok | {:error, atom()}
  def verify(raw_body, signature_header, signing_secret, opts \\ []) do
    max_age = Keyword.get(opts, :max_age, @default_max_age)

    with {:ok, ts, h1} <- parse_signature(signature_header),
         :ok <- check_replay(ts, max_age),
         :ok <- check_hmac(raw_body, ts, h1, signing_secret) do
      :ok
    end
  end

  @doc "Parse the Paddle-Signature header into {timestamp, hash}."
  def parse_signature(header) when is_binary(header) do
    parts =
      header
      |> String.split(";")
      |> Enum.reduce(%{}, fn part, acc ->
        case String.split(part, "=", parts: 2) do
          [key, value] -> Map.put(acc, key, value)
          _ -> acc
        end
      end)

    case {Map.get(parts, "ts"), Map.get(parts, "h1")} do
      {nil, _} -> {:error, :missing_timestamp}
      {_, nil} -> {:error, :missing_hash}
      {ts, h1} -> {:ok, ts, h1}
    end
  end

  def parse_signature(_), do: {:error, :invalid_header}

  defp check_replay(ts_string, max_age) do
    case Integer.parse(ts_string) do
      {ts, ""} ->
        now = System.system_time(:second)
        age = now - ts

        if age <= max_age and age >= -30 do
          :ok
        else
          {:error, :replay_attack}
        end

      _ ->
        {:error, :invalid_timestamp}
    end
  end

  defp check_hmac(raw_body, ts, expected_h1, signing_secret) do
    signed_payload = "#{ts}:#{raw_body}"

    computed =
      :crypto.mac(:hmac, :sha256, signing_secret, signed_payload)
      |> Base.encode16(case: :lower)

    if Plug.Crypto.secure_compare(computed, expected_h1) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end
end
