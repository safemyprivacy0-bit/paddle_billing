defmodule PaddleBilling.Error do
  @moduledoc """
  Error struct for PaddleBilling API errors.
  """

  @type t :: %__MODULE__{
          type: atom(),
          code: String.t() | nil,
          detail: String.t() | nil,
          status: integer() | nil
        }

  defstruct [:type, :code, :detail, :status]

  @doc "Build an error from a Paddle API error response."
  def from_response(%{"error" => error}, status) do
    %__MODULE__{
      type: :api_error,
      code: error["code"],
      detail: error["detail"] || error["message"],
      status: status
    }
  end

  def from_response(_body, status) do
    %__MODULE__{
      type: :api_error,
      code: "unknown",
      detail: "Unexpected error response",
      status: status
    }
  end

  def network_error(reason) do
    %__MODULE__{
      type: :network_error,
      code: nil,
      detail: inspect(reason),
      status: nil
    }
  end

  def rate_limited(retry_after) do
    %__MODULE__{
      type: :rate_limited,
      code: "rate_limited",
      detail: "Rate limited. Retry after #{retry_after}s.",
      status: 429
    }
  end
end
