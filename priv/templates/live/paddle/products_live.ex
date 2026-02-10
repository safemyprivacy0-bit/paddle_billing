defmodule RawrPhoenixWeb.Paddle.ProductsLive do
  @moduledoc "Admin LiveView for managing Paddle products."
  use RawrPhoenixWeb, :live_view

  alias RawrPhoenix.Billing
  alias RawrPhoenix.Billing.PaddleProduct

  import RawrPhoenixWeb.Components.PaddleComponents

  @plan_levels ~w(undefined free starter growth ultimate)
  @app_roles ~w(none subscription subscription_addon one_time_payment)
  @tax_categories ~w(standard digital-goods saas software)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Billing - Products")
     |> assign(:products, list_products())
     |> assign(:plan_levels, @plan_levels)
     |> assign(:app_roles, @app_roles)
     |> assign(:tax_categories, @tax_categories)
     |> assign(:syncing, false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :product, nil)
  end

  defp apply_action(socket, :new, _params) do
    assign(socket, :product, %PaddleProduct{status: "active"})
  end

  defp apply_action(socket, :edit, %{"paddle_id" => paddle_id}) do
    assign(socket, :product, Billing.get_product!(paddle_id))
  end

  @impl true
  def handle_event("sync", _params, socket) do
    socket = assign(socket, :syncing, true)

    case Billing.sync_from_paddle(:products) do
      {:ok, _results} ->
        {:noreply,
         socket
         |> assign(:products, list_products())
         |> assign(:syncing, false)
         |> put_flash(:info, "Products synced from Paddle.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:syncing, false)
         |> put_flash(:error, "Sync failed: #{inspect(reason)}")}
    end
  end

  def handle_event("archive", %{"paddle-id" => paddle_id}, socket) do
    product = Billing.get_product!(paddle_id)

    case Billing.archive_product(product) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:products, list_products())
         |> put_flash(:info, "Product archived.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  def handle_event("activate", %{"paddle-id" => paddle_id}, socket) do
    product = Billing.get_product!(paddle_id)

    case Billing.activate_product(product) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:products, list_products())
         |> put_flash(:info, "Product activated.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  def handle_event("save", %{"product" => params}, socket) do
    case socket.assigns.live_action do
      :new -> create_product(socket, params)
      :edit -> update_product(socket, params)
    end
  end

  defp create_product(socket, params) do
    case Billing.create_product(params) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> assign(:products, list_products())
         |> put_flash(:info, "Product created.")
         |> push_patch(to: ~p"/admin/billing")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  defp update_product(socket, params) do
    product = socket.assigns.product

    case Billing.update_product(product, params) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> assign(:products, list_products())
         |> put_flash(:info, "Product updated.")
         |> push_patch(to: ~p"/admin/billing")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  defp list_products do
    Billing.list_products(preload: [:paddle_prices])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_container>
      <.billing_header syncing={@syncing} />
      <.product_form
        :if={@live_action in [:new, :edit]}
        product={@product}
        action={@live_action}
        plan_levels={@plan_levels}
        app_roles={@app_roles}
        tax_categories={@tax_categories}
      />
      <.products_table :if={@live_action == :index} products={@products} />
    </.page_container>
    """
  end

  # ── Function Components ─────────────────────────────────────────

  defp billing_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-2xl font-bold">Billing - Products</h1>
        <div class="flex gap-2 mt-2">
          <.link navigate={~p"/admin/billing"} class="btn btn-sm btn-primary btn-soft">Products</.link>
          <.link navigate={~p"/admin/billing/discounts"} class="btn btn-sm btn-ghost">Discounts</.link>
          <.link navigate={~p"/admin/billing/sync"} class="btn btn-sm btn-ghost">Sync</.link>
        </div>
      </div>
      <div class="flex gap-2">
        <button phx-click="sync" class="btn btn-sm btn-outline" disabled={@syncing}>
          <span :if={@syncing} class="loading loading-spinner loading-xs"></span>
          {if @syncing, do: "Syncing...", else: "Sync from Paddle"}
        </button>
        <.link navigate={~p"/admin/billing/products/new"} class="btn btn-sm btn-primary">
          New Product
        </.link>
      </div>
    </div>
    """
  end

  defp products_table(assigns) do
    ~H"""
    <div :if={@products == []} class="text-center py-12 text-base-content/50">
      No products yet. Create one or sync from Paddle.
    </div>

    <div :if={@products != []} class="overflow-x-auto">
      <table class="table w-full">
        <thead>
          <tr>
            <th>Name</th>
            <th>Status</th>
            <th>App Role</th>
            <th>Plan Level</th>
            <th>Prices</th>
            <th>Synced</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <.product_row :for={product <- @products} product={product} />
        </tbody>
      </table>
    </div>
    """
  end

  defp product_row(assigns) do
    ~H"""
    <tr>
      <td>
        <div>
          <span class="font-medium">{@product.name}</span>
          <p :if={@product.description} class="text-xs text-base-content/50 truncate max-w-xs">
            {@product.description}
          </p>
        </div>
      </td>
      <td><.status_badge status={@product.status} /></td>
      <td><span class="badge badge-ghost badge-sm">{@product.app_role}</span></td>
      <td><span class="badge badge-ghost badge-sm">{@product.plan_level}</span></td>
      <td>
        <.link
          navigate={~p"/admin/billing/products/#{@product.paddle_id}/prices"}
          class="link link-primary text-sm"
        >
          {length(@product.paddle_prices)} prices
        </.link>
      </td>
      <td><.sync_status synced_at={@product.synced_at} /></td>
      <td>
        <div class="flex gap-1">
          <.link
            navigate={~p"/admin/billing/products/#{@product.paddle_id}/edit"}
            class="btn btn-xs btn-ghost"
          >
            Edit
          </.link>
          <button
            :if={@product.status == "active"}
            phx-click="archive"
            phx-value-paddle-id={@product.paddle_id}
            data-confirm="Archive this product?"
            class="btn btn-xs btn-ghost text-error"
          >
            Archive
          </button>
          <button
            :if={@product.status == "archived"}
            phx-click="activate"
            phx-value-paddle-id={@product.paddle_id}
            class="btn btn-xs btn-ghost text-success"
          >
            Activate
          </button>
        </div>
      </td>
    </tr>
    """
  end

  defp product_form(assigns) do
    ~H"""
    <.card class="mb-6">
      <div class="card-body p-5">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold">
            {if @action == :new, do: "New Product", else: "Edit Product"}
          </h2>
          <.link navigate={~p"/admin/billing"} class="btn btn-sm btn-ghost">Cancel</.link>
        </div>

        <form novalidate phx-submit="save" class="space-y-4">
          <div class="form-control">
            <label class="label"><span class="label-text">Name</span></label>
            <input
              type="text"
              name="product[name]"
              value={@product.name}
              class="input input-bordered w-full"
              required
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text">Description</span></label>
            <textarea name="product[description]" class="textarea textarea-bordered w-full" rows="3">{@product.description}</textarea>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Tax Category</span></label>
              <select name="product[tax_category]" class="select select-bordered w-full">
                <option value="">Select...</option>
                <option
                  :for={cat <- @tax_categories}
                  value={cat}
                  selected={@product.tax_category == cat}
                >
                  {cat}
                </option>
              </select>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Image URL</span></label>
              <input
                type="url"
                name="product[image_url]"
                value={@product.image_url}
                class="input input-bordered w-full"
              />
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text">App Role</span></label>
              <select name="product[app_role]" class="select select-bordered w-full">
                <option
                  :for={role <- @app_roles}
                  value={role}
                  selected={to_string(@product.app_role) == role}
                >
                  {role}
                </option>
              </select>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Plan Level</span></label>
              <select name="product[plan_level]" class="select select-bordered w-full">
                <option
                  :for={level <- @plan_levels}
                  value={level}
                  selected={to_string(@product.plan_level) == level}
                >
                  {level}
                </option>
              </select>
            </div>
          </div>

          <div class="flex justify-end pt-2">
            <button type="submit" class="btn btn-primary">
              {if @action == :new, do: "Create Product", else: "Update Product"}
            </button>
          </div>
        </form>
      </div>
    </.card>
    """
  end
end
