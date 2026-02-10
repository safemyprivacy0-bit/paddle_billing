defmodule PaddleBilling.Config do
  @moduledoc """
  Configuration for PaddleBilling.

  Reads from Application env under `:paddle_billing, :config`.
  Supports sandbox and production environments.
  """

  @sandbox_url "https://sandbox-api.paddle.com"
  @production_url "https://api.paddle.com"

  def api_key do
    config()[:api_key] || raise "PADDLE_BILLING_API_KEY not configured"
  end

  def client_token do
    config()[:client_token]
  end

  def signing_secret do
    config()[:signing_secret] || raise "PADDLE_BILLING_SIGNING_SECRET not configured"
  end

  def environment do
    case config()[:environment] do
      env when env in ["production", :production] -> :production
      _ -> :sandbox
    end
  end

  def base_url do
    case environment() do
      :production -> @production_url
      :sandbox -> @sandbox_url
    end
  end

  defp config do
    Application.get_env(:paddle_billing, :config, [])
  end
end
