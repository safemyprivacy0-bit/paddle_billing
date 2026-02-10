defmodule RawrPhoenixWeb.Paddle.SyncLive do
  @moduledoc "Admin LiveView for Paddle sync dashboard - drift detection and reconciliation."
  use RawrPhoenixWeb, :live_view

  alias RawrPhoenix.Billing

  import RawrPhoenixWeb.Components.PaddleComponents

  @resource_types [:products, :prices, :discounts]
  @strategies [{"Paddle Wins", "paddle_wins"}, {"Local Wins", "local_wins"}, {"Newest Wins", "newest_wins"}]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Billing - Sync")
     |> assign(:resource_types, @resource_types)
     |> assign(:strategies, @strategies)
     |> assign(:drift_results, %{})
     |> assign(:syncing, nil)
     |> assign(:reconciling, nil)
     |> assign(:last_synced, load_last_synced())}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("detect_drift", %{"type" => type}, socket) do
    type_atom = String.to_existing_atom(type)

    case Billing.detect_drift(type_atom) do
      {:ok, results} ->
        drift_results = Map.put(socket.assigns.drift_results, type_atom, results)
        {:noreply, assign(socket, :drift_results, drift_results)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Drift detection failed: #{inspect(reason)}")}
    end
  end

  def handle_event("sync_type", %{"type" => type}, socket) do
    type_atom = String.to_existing_atom(type)
    socket = assign(socket, :syncing, type_atom)

    case Billing.sync_from_paddle(type_atom) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:syncing, nil)
         |> assign(:last_synced, load_last_synced())
         |> put_flash(:info, "#{type} synced from Paddle.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:syncing, nil)
         |> put_flash(:error, "Sync failed: #{inspect(reason)}")}
    end
  end

  def handle_event("sync_all", _params, socket) do
    socket = assign(socket, :syncing, :all)

    case Billing.sync_all_from_paddle() do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:syncing, nil)
         |> assign(:last_synced, load_last_synced())
         |> put_flash(:info, "All resources synced from Paddle.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:syncing, nil)
         |> put_flash(:error, "Full sync failed: #{inspect(reason)}")}
    end
  end

  def handle_event("reconcile", %{"type" => type, "strategy" => strategy}, socket) do
    type_atom = String.to_existing_atom(type)
    strategy_atom = String.to_existing_atom(strategy)
    socket = assign(socket, :reconciling, type_atom)

    case Billing.reconcile(type_atom, strategy_atom) do
      {:ok, results} ->
        resolved = Enum.count(results)

        {:noreply,
         socket
         |> assign(:reconciling, nil)
         |> assign(:drift_results, Map.delete(socket.assigns.drift_results, type_atom))
         |> assign(:last_synced, load_last_synced())
         |> put_flash(:info, "Reconciled #{resolved} #{type} records.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:reconciling, nil)
         |> put_flash(:error, "Reconciliation failed: #{inspect(reason)}")}
    end
  end

  defp load_last_synced do
    %{
      products: last_synced_for(:products),
      prices: last_synced_for(:prices),
      discounts: last_synced_for(:discounts)
    }
  end

  defp last_synced_for(type) do
    records =
      case type do
        :products -> Billing.list_products()
        :prices -> Billing.list_prices()
        :discounts -> Billing.list_discounts()
      end

    records
    |> Enum.map(& &1.synced_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_container>
      <.sync_header syncing={@syncing} />

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-8">
        <.resource_card
          :for={type <- @resource_types}
          type={type}
          last_synced={@last_synced[type]}
          syncing={@syncing}
          reconciling={@reconciling}
          drift_results={@drift_results[type]}
          strategies={@strategies}
        />
      </div>

      <.drift_details
        :for={{type, results} <- @drift_results}
        type={type}
        results={results}
      />
    </.page_container>
    """
  end

  # ── Function Components ─────────────────────────────────────────

  defp sync_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-2xl font-bold">Billing - Sync Dashboard</h1>
        <div class="flex gap-2 mt-2">
          <.link navigate={~p"/admin/billing"} class="btn btn-sm btn-ghost">Products</.link>
          <.link navigate={~p"/admin/billing/discounts"} class="btn btn-sm btn-ghost">Discounts</.link>
          <.link navigate={~p"/admin/billing/sync"} class="btn btn-sm btn-primary btn-soft">Sync</.link>
        </div>
      </div>
      <button phx-click="sync_all" class="btn btn-sm btn-primary" disabled={@syncing != nil}>
        <span :if={@syncing == :all} class="loading loading-spinner loading-xs"></span>
        {if @syncing == :all, do: "Syncing All...", else: "Sync All from Paddle"}
      </button>
    </div>
    """
  end

  defp resource_card(assigns) do
    assigns = assign(assigns, :drift_summary, summarize_drift(assigns.drift_results))

    ~H"""
    <.card>
      <div class="card-body p-5">
        <div class="flex items-center justify-between mb-3">
          <h3 class="font-semibold capitalize">{@type}</h3>
          <.sync_status synced_at={@last_synced} />
        </div>

        <div :if={@drift_summary} class="mb-3 space-y-1">
          <div class="flex items-center justify-between text-sm">
            <span class="text-success">In sync</span>
            <span class="font-mono">{@drift_summary.in_sync}</span>
          </div>
          <div class="flex items-center justify-between text-sm">
            <span class="text-warning">Drifted</span>
            <span class="font-mono">{@drift_summary.drifted}</span>
          </div>
          <div class="flex items-center justify-between text-sm">
            <span class="text-info">Local only</span>
            <span class="font-mono">{@drift_summary.local_only}</span>
          </div>
          <div class="flex items-center justify-between text-sm">
            <span class="text-error">Paddle only</span>
            <span class="font-mono">{@drift_summary.paddle_only}</span>
          </div>
        </div>

        <div class="space-y-2">
          <button
            phx-click="detect_drift"
            phx-value-type={@type}
            class="btn btn-sm btn-outline w-full"
          >
            Detect Drift
          </button>

          <button
            phx-click="sync_type"
            phx-value-type={@type}
            class="btn btn-sm btn-outline w-full"
            disabled={@syncing != nil}
          >
            <span :if={@syncing == @type} class="loading loading-spinner loading-xs"></span>
            Sync from Paddle
          </button>

          <div :if={@drift_summary && @drift_summary.drifted > 0} class="pt-1">
            <form phx-submit="reconcile" class="flex gap-2">
              <input type="hidden" name="type" value={@type} />
              <select name="strategy" class="select select-bordered select-sm flex-1">
                <option :for={{label, val} <- @strategies} value={val}>{label}</option>
              </select>
              <button
                type="submit"
                class="btn btn-sm btn-warning"
                disabled={@reconciling == @type}
              >
                <span :if={@reconciling == @type} class="loading loading-spinner loading-xs"></span>
                Reconcile
              </button>
            </form>
          </div>
        </div>
      </div>
    </.card>
    """
  end

  defp drift_details(assigns) do
    ~H"""
    <.card class="mb-4">
      <div class="card-body p-5">
        <h3 class="font-semibold capitalize mb-3">{@type} - Drift Details</h3>
        <div class="overflow-x-auto">
          <table class="table table-sm w-full">
            <thead>
              <tr>
                <th>ID</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{item, status} <- @results}>
                <td class="font-mono text-sm">{drift_item_id(item)}</td>
                <td><.drift_indicator status={status} /></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </.card>
    """
  end

  defp drift_item_id(%{paddle_id: id}), do: id
  defp drift_item_id(%{"id" => id}), do: id
  defp drift_item_id(_), do: "unknown"

  defp summarize_drift(nil), do: nil

  defp summarize_drift(results) do
    Enum.reduce(results, %{in_sync: 0, drifted: 0, local_only: 0, paddle_only: 0}, fn
      {_, :in_sync}, acc -> Map.update!(acc, :in_sync, &(&1 + 1))
      {_, :drifted}, acc -> Map.update!(acc, :drifted, &(&1 + 1))
      {_, :local_only}, acc -> Map.update!(acc, :local_only, &(&1 + 1))
      {_, :paddle_only}, acc -> Map.update!(acc, :paddle_only, &(&1 + 1))
      _, acc -> acc
    end)
  end
end
