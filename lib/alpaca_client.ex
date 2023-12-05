defmodule AlpacaInvestors.AlpacaClient do
  @moduledoc """
  A helper module for running basic test helping functions for end-to-end tests.
  Note: Not to be used in prod and dev
  """

  @starting_cash "10000"
  @activated_email_prefix "activated_test_investor_email"

  def client do
    [base_url: base_url, key: key, secret: secret] =
      Application.fetch_env!(:alpaca_investors, AlpacaInvestors)

    access_token = Base.encode64("#{key}:#{secret}")

    Tesla.client([
      {Tesla.Middleware.BaseUrl, base_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"Authorization", "Basic #{access_token}"}]}
    ])
  end

  def get_active_accounts(num_investor_accounts \\ 5) do
    client = client()

    with {:ok, %Tesla.Env{status: 200, body: accounts}} <-
           Tesla.get(client, "/v1/accounts?status=ACTIVE&query=exhausted_test_investor_email"),
         accounts <- Stream.filter(accounts, &has_no_positions(client, &1)),
         accounts <- Stream.filter(accounts, &has_enough_cash(client, &1)),
         accounts <- Enum.take(accounts, num_investor_accounts) do
      {:ok, accounts}
    else
      [] -> {:error, :no_investor_accounts}
      {:ok, %Tesla.Env{body: error_body}} -> {:error, error_body}
    end
  end

  def create_funded_user() do
    client = client()

    with {:ok, %Tesla.Env{status: 200, body: %{"id" => account_id}}} <-
           Tesla.post(client, "/v1/accounts/", %{
             contact: %{
               email_address: rand_activated_email(),
               phone_number: "555-666-7788",
               street_address: ["20 N San Mateo Dr"],
               city: "San Mateo",
               state: "MT",
               postal_code: "94401",
               country: "USA"
             },
             identity: %{
               given_name: "John",
               family_name: "Doe",
               tax_id: "666-55-4321",
               tax_id_type: "USA_SSN",
               date_of_birth: "1990-01-01",
               country_of_tax_residence: "USA",
               funding_source: ["employment_income"]
             },
             disclosures: %{
               is_control_person: false,
               is_affiliated_exchange_or_finra: true,
               is_politically_exposed: false,
               immediate_family_exposed: false
             },
             agreements: [
               %{
                 agreement: "customer_agreement",
                 signed_at: "2020-09-11T18:13:44Z",
                 ip_address: "185.13.21.99",
                 revision: "19.2022.02"
               },
               %{
                 agreement: "crypto_agreement",
                 signed_at: "2020-09-11T18:13:44Z",
                 ip_address: "185.13.21.99",
                 revision: "04.2021.10"
               }
             ]
           }),
         {:ok, %Tesla.Env{status: 200, body: %{"id" => relationship_id}}} <-
           Tesla.post(client, "/v1/accounts/#{account_id}/ach_relationships", %{
             account_owner_name: "Awesome Alpaca",
             bank_account_type: "CHECKING",
             bank_account_number: "32131231abc",
             bank_routing_number: "121000358",
             nickname: "Bank of America Checking"
           }),
         {:ok, _} <-
           Tesla.post(client, "/v1/accounts/#{account_id}/transfers", %{
             transfer_type: "ach",
             relationship_id: relationship_id,
             amount: @starting_cash,
             direction: "INCOMING"
           }) do
      :ok
    else
      {:ok, %Tesla.Env{body: error_body}} -> {:error, error_body}
    end
  end

  @doc """
  We mark "exhausted" investors by swapping out the email address.
  We can later close these accounts without slowing down E2E.Alpaca.get_active_integration_accounts/2
  """
  def exhaust_investor(investor_id) do
    case Tesla.patch(client(), "/v1/accounts/#{investor_id}", %{
           contact: %{email_address: rand_exhausted_email()}
         }) do
      {:ok, %Tesla.Env{status: 200}} -> :ok
      {:ok, %Tesla.Env{body: error_body}} -> {:error, error_body}
    end
  end

  def create_sell_order(sym, qty, partner_investor_id) do
    create_order(sym, qty, "sell", partner_investor_id)
  end

  def create_buy_order(sym, qty, partner_investor_id) do
    create_order(sym, qty, "buy", partner_investor_id)
  end

  @success_statuses [
    "new",
    "accepted",
    "pending_new",
    "accepted_for_bidding",
    "partially_filled",
    "filled"
  ]

  def create_order(sym, qty, side, partner_investor_id)
      when is_binary(sym) and is_binary(qty) and is_binary(partner_investor_id) do
    case Tesla.post(client(), "/v1/trading/accounts/#{partner_investor_id}/orders", %{
           symbol: sym,
           qty: qty,
           side: side,
           type: "market",
           time_in_force: "day"
         }) do
      {:ok, %Tesla.Env{status: 200, body: %{"status" => status} = body}}
      when status in @success_statuses ->
        {:ok, body}

      {:ok, %Tesla.Env{body: error_body}} ->
        {:error, error_body}
    end
  end

  def get_journals_from_account(investor_id) do
    case Tesla.get(
           client(),
           "/v1/journals?from_account=#{investor_id}&after=#{Date.utc_today()}"
         ) do
      {:ok, %Tesla.Env{status: 200, body: body}} -> {:ok, body}
      {:ok, %Tesla.Env{body: error_body}} -> {:error, error_body}
    end
  end

  def get_journals_to_account(investor_id) do
    case Tesla.get(client(), "/v1/journals?to_account=#{investor_id}") do
      {:ok, %Tesla.Env{status: 200, body: body}} -> {:ok, body}
      {:ok, %Tesla.Env{body: error_body}} -> {:error, error_body}
    end
  end

  defp rand_activated_email, do: "#{@activated_email_prefix}#{UUID.uuid4(:hex)}@email.com"

  defp rand_exhausted_email, do: "exhausted_test_investor_email#{UUID.uuid4(:hex)}@email.com"

  defp has_enough_cash(client, %{"id" => id}) do
    case Tesla.get(client, "/v1/trading/accounts/#{id}/account") do
      {:ok, %Tesla.Env{status: 200, body: %{"cash_transferable" => @starting_cash}}} -> true
      {:ok, %Tesla.Env{}} -> false
    end
  end

  defp has_no_positions(client, %{"id" => id}) do
    case Tesla.get(client, "/v1/trading/accounts/#{id}/positions") do
      {:ok, %Tesla.Env{status: 200, body: []}} -> true
      {:ok, %Tesla.Env{}} -> false
    end
  end
end
