defmodule Mix.Tasks.PaddleBilling.Install do
  @moduledoc """
  Installs PaddleBilling admin panel LiveViews into your project.

  Copies template files from `priv/templates/` to your project's
  web directory, replacing module names to match your application.

  ## Usage

      mix paddle_billing.install

  ## Options

      --web-module MyAppWeb    (default: auto-detected from mix.exs)
      --context-module MyApp.Billing  (default: auto-detected)
      --no-routes              Skip route injection, print instructions instead
  """
  use Mix.Task

  @shortdoc "Installs PaddleBilling admin panel LiveViews into your project"

  @files [
    {"live/paddle/products_live.ex", "live/paddle/products_live.ex"},
    {"live/paddle/prices_live.ex", "live/paddle/prices_live.ex"},
    {"live/paddle/discounts_live.ex", "live/paddle/discounts_live.ex"},
    {"live/paddle/sync_live.ex", "live/paddle/sync_live.ex"},
    {"live/paddle/checkout_live.ex", "live/paddle/checkout_live.ex"},
    {"components/paddle_components.ex", "components/paddle_components.ex"}
  ]

  @js_files [
    {"js/paddle_checkout.js", "js/hooks/paddle_checkout.js"}
  ]

  @route_snippet """
      # PaddleBilling Admin Panel
      live_session :admin_billing, on_mount: [{__WEB_MODULE__.LiveAuth, :require_admin}] do
        live "/admin/billing", __WEB_MODULE__.Paddle.ProductsLive, :index
        live "/admin/billing/products/new", __WEB_MODULE__.Paddle.ProductsLive, :new
        live "/admin/billing/products/:paddle_id/edit", __WEB_MODULE__.Paddle.ProductsLive, :edit
        live "/admin/billing/products/:paddle_id/prices", __WEB_MODULE__.Paddle.PricesLive, :index
        live "/admin/billing/products/:paddle_id/prices/new", __WEB_MODULE__.Paddle.PricesLive, :new
        live "/admin/billing/products/:paddle_id/prices/:price_paddle_id/edit", __WEB_MODULE__.Paddle.PricesLive, :edit
        live "/admin/billing/discounts", __WEB_MODULE__.Paddle.DiscountsLive, :index
        live "/admin/billing/discounts/new", __WEB_MODULE__.Paddle.DiscountsLive, :new
        live "/admin/billing/discounts/:paddle_id/edit", __WEB_MODULE__.Paddle.DiscountsLive, :edit
        live "/admin/billing/sync", __WEB_MODULE__.Paddle.SyncLive, :index
      end

      # PaddleBilling Checkout (authenticated users)
      live_session :paddle_checkout, on_mount: [{__WEB_MODULE__.LiveAuth, :require_authenticated}] do
        live "/checkout", __WEB_MODULE__.Paddle.CheckoutLive, :index
      end
  """

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [web_module: :string, context_module: :string, no_routes: :boolean]
      )

    app_name = detect_app_name()
    web_module = opts[:web_module] || detect_web_module(app_name)
    context_module = opts[:context_module] || detect_context_module(app_name)
    inject_routes? = !opts[:no_routes]

    template_dir = Application.app_dir(:paddle_billing, "priv/templates")

    Mix.shell().info("Installing PaddleBilling admin panel...")
    Mix.shell().info("  App: #{app_name}")
    Mix.shell().info("  Web module: #{web_module}")
    Mix.shell().info("  Context module: #{context_module}")
    Mix.shell().info("")

    web_dir = "lib/#{Macro.underscore(web_module)}"

    # Copy LiveView / component templates to web directory
    Enum.each(@files, fn {src, dest} ->
      source_path = Path.join(template_dir, src)
      target_path = Path.join(web_dir, dest)

      content =
        source_path
        |> File.read!()
        |> String.replace("RawrPhoenixWeb", web_module)
        |> String.replace("RawrPhoenix.Billing", context_module)
        |> String.replace("RawrPhoenixWeb.LiveAuth", "#{web_module}.LiveAuth")

      target_dir = Path.dirname(target_path)
      File.mkdir_p!(target_dir)
      File.write!(target_path, content)
      Mix.shell().info("  Created #{target_path}")
    end)

    # Copy JS hooks to assets directory
    Enum.each(@js_files, fn {src, dest} ->
      source_path = Path.join(template_dir, src)
      target_path = Path.join("assets", dest)

      target_dir = Path.dirname(target_path)
      File.mkdir_p!(target_dir)
      File.cp!(source_path, target_path)
      Mix.shell().info("  Created #{target_path}")
    end)

    if inject_routes? do
      inject_routes(web_module)
    else
      print_route_instructions(web_module)
    end

    Mix.shell().info("")
    Mix.shell().info("Installation complete!")
    Mix.shell().info("")
    Mix.shell().info("Next steps:")
    Mix.shell().info("  1. Verify routes in your router.ex")
    Mix.shell().info("  2. Ensure LiveAuth :require_admin on_mount hook exists")
    Mix.shell().info("  3. Add to assets/js/hooks/index.js:")
    Mix.shell().info("     import PaddleCheckout from \"./paddle_checkout\"")
    Mix.shell().info("     // and add PaddleCheckout to the export object")
    Mix.shell().info("  4. Start your server: mix phx.server")
    Mix.shell().info("  5. Visit /admin/billing")
  end

  defp detect_app_name do
    Mix.Project.config()[:app] |> to_string()
  end

  defp detect_web_module(app_name) do
    app_name
    |> Macro.camelize()
    |> Kernel.<>("Web")
  end

  defp detect_context_module(app_name) do
    app_name
    |> Macro.camelize()
    |> Kernel.<>(".Billing")
  end

  defp inject_routes(web_module) do
    router_path = "lib/#{Macro.underscore(web_module)}/router.ex"

    if File.exists?(router_path) do
      content = File.read!(router_path)
      routes = String.replace(@route_snippet, "__WEB_MODULE__", web_module)

      if String.contains?(content, "Paddle.ProductsLive") do
        Mix.shell().info("\n  Routes already present in #{router_path} - skipping.")
      else
        # Try to inject before the final `end` of the router module
        case String.split(content, "\nend", parts: 2) do
          [before, after_end] ->
            new_content = before <> "\n" <> routes <> "\nend" <> after_end
            File.write!(router_path, new_content)
            Mix.shell().info("\n  Routes injected into #{router_path}")

          _ ->
            Mix.shell().info("\n  Could not auto-inject routes.")
            print_route_instructions(web_module)
        end
      end
    else
      Mix.shell().info("\n  Router not found at #{router_path}")
      print_route_instructions(web_module)
    end
  end

  defp print_route_instructions(web_module) do
    routes = String.replace(@route_snippet, "__WEB_MODULE__", web_module)

    Mix.shell().info("""

    Add the following routes to your router.ex:

    #{routes}
    """)
  end
end
