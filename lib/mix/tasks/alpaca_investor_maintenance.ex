defmodule Mix.Tasks.AlpacaInvestor.Maintenance do
  @moduledoc """
  Every so often, we will need to do some maintenance on our alpaca account to maintain our end to end tests.
  This task will clear out investor accounts that have already been used by our end to end tests
  It will also add some funds into the alpaca_belay_account_id to insure money can still be moved around as needed.
  """
  use Mix.Task

  @requirements ["app.config"]

  import AlpacaInvestors.AlpacaClient, only: [client: 0]

  require Logger

  @impl Mix.Task
  def run([alpaca_belay_account_id]) do
    Application.ensure_all_started(:hackney)

    client = client()

    Logger.info("Exhausting used E2E investor accounts...")

    # Get all accounts
    {:ok, %Tesla.Env{status: 200, body: exhausted_accounts}} =
      Tesla.get(client, "/v1/accounts?status=ACTIVE&query=exhausted_test_email")

    for %{"id" => exhausted_account_id} <- exhausted_accounts do
      # Find next step needed to close account
      func = get_next_exhaust_step(client, exhausted_account_id)
      # Apply next step
      :ok = apply(__MODULE__, func, [client, exhausted_account_id])
    end

    Logger.info("Adding funds to alpaca_belay_account_id...")

    with {:ok, [%{"id" => relationship_id} | _]} <-
           fetch_ach_relationships(client, alpaca_belay_account_id),
         {:ok, %Tesla.Env{status: 200}} <-
           Tesla.post(client, "v1/accounts/#{alpaca_belay_account_id}/transfers", %{
             transfer_type: "ach",
             relationship_id: relationship_id,
             amount: "500",
             direction: "INCOMING"
           }) do
      Logger.info("Funds transferred")
    end
  end

  @doc """
  To close an account, we need to do the following:
  -> Sell all positions if any
  -> Withdraw all cash once all cash is withdrawable
  -> Close account only once the equity and cash are zero
  """
  def get_next_exhaust_step(client, account_id) do
    cond do
      has_positions(client, account_id) -> :sell_positions
      all_cash_is_withdrawable(client, account_id) -> :withdraw_cash
      all_cash_is_withdrawn(client, account_id) -> :close_account
      true -> :skip
    end
  end

  def sell_positions(client, account_id) do
    case Tesla.delete(client, "/v1/trading/accounts/#{account_id}/positions?cancel_orders=true") do
      {:ok, %Tesla.Env{status: 207}} -> :ok
      {:ok, %Tesla.Env{status: 500}} -> :error
    end
  end

  def withdraw_cash(client, account_id) do
    with {:ok, [%{"id" => relationship_id} | _]} <- fetch_ach_relationships(client, account_id),
         {:ok, %Tesla.Env{status: 200, body: %{"cash_withdrawable" => cash}}} <-
           Tesla.get(client, "/v1/trading/accounts/#{account_id}/account"),
         {:ok, %Tesla.Env{status: 200}} <-
           Tesla.post(client, "/v1/accounts/#{account_id}/transfers", %{
             transfer_type: "ach",
             direction: "OUTGOING",
             relationship_id: relationship_id,
             amount: cash
           }) do
      :ok
    end
  end

  def close_account(client, account_id) do
    case Tesla.post(client, "/v1/accounts/#{account_id}/actions/close", %{}) do
      {:ok, %Tesla.Env{status: 204}} -> :ok
      {:ok, %Tesla.Env{body: error}} -> {:error, error}
    end
  end

  def skip(_client, _account_id), do: :ok

  defp fetch_ach_relationships(client, account_id) do
    case Tesla.get(client, "/v1/accounts/#{account_id}/ach_relationships") do
      {:ok, %Tesla.Env{status: 200, body: body}} -> {:ok, body}
      {:ok, %Tesla.Env{body: body}} -> {:error, body}
    end
  end

  defp has_positions(client, account_id) do
    case Tesla.get(client, "/v1/trading/accounts/#{account_id}/positions") do
      {:ok, %Tesla.Env{status: 200, body: positions}} when positions != [] -> true
      {:ok, %Tesla.Env{status: 200, body: []}} -> false
    end
  end

  defp all_cash_is_withdrawable(client, account_id) do
    case Tesla.get(client, "/v1/trading/accounts/#{account_id}/account") do
      {:ok,
       %Tesla.Env{
         status: 200,
         body: %{"equity" => equity, "cash_withdrawable" => cash_withdrawable}
       }} ->
        equity == cash_withdrawable and cash_withdrawable != "0"

      {:ok, %Tesla.Env{}} ->
        false
    end
  end

  defp all_cash_is_withdrawn(client, account_id) do
    case Tesla.get(client, "/v1/trading/accounts/#{account_id}/account") do
      {:ok, %Tesla.Env{status: 200, body: %{"equity" => "0"}}} -> true
      {:ok, %Tesla.Env{}} -> false
    end
  end
end
