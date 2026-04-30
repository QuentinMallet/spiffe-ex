defmodule SpiffeEx.OidcClient do
  require Logger

  @jwt_bearer_grant "urn:ietf:params:oauth:grant-type:jwt-bearer"
  @token_exchange_grant "urn:ietf:params:oauth:grant-type:token-exchange"
  @jwt_token_type "urn:ietf:params:oauth:token-type:jwt"

  @doc """
  Retrieves an OIDC token using the SVID JWT as a bearer assertion (RFC 7523)
  or as a token exchange subject (RFC 8693).
  """
  def retrieve_token(svid_jwt, opts) do
    flow = Keyword.get(opts, :flow, :client_assertion)
    retry_policy = Keyword.get(opts, :retry_policy, max: 3, base_ms: 1000)
    do_retrieve_with_retry(svid_jwt, opts, flow, retry_policy, 0)
  end

  defp do_retrieve_with_retry(svid_jwt, opts, flow, retry_policy, attempt) do
    case do_retrieve(svid_jwt, opts, flow) do
      {:ok, token} ->
        :telemetry.execute([:spiffe_ex, :token, :refresh], %{}, %{flow: flow})
        {:ok, token}

      {:error, reason}
      when reason in [:jwks_fetch_failed, :idp_unreachable, :network_error] ->
        max = Keyword.get(retry_policy, :max, 3)
        base_ms = Keyword.get(retry_policy, :base_ms, 1000)

        if attempt < max do
          delay = round(base_ms * :math.pow(2, attempt))
          Process.sleep(delay)
          do_retrieve_with_retry(svid_jwt, opts, flow, retry_policy, attempt + 1)
        else
          :telemetry.execute([:spiffe_ex, :error], %{}, %{reason: :idp_unreachable})
          {:error, :idp_unreachable}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_retrieve(svid_jwt, opts, :client_assertion) do
    client_id = Keyword.fetch!(opts, :client_id)

    with {:ok, token_endpoint} <- fetch_token_endpoint(opts) do
      body =
        URI.encode_query(%{
          "grant_type" => @jwt_bearer_grant,
          "assertion" => svid_jwt,
          "client_id" => client_id
        })

      post_token_request(token_endpoint, body)
    end
  end

  defp do_retrieve(svid_jwt, opts, :token_exchange) do
    client_id = Keyword.fetch!(opts, :client_id)

    with {:ok, token_endpoint} <- fetch_token_endpoint(opts) do
      body =
        URI.encode_query(%{
          "grant_type" => @token_exchange_grant,
          "subject_token" => svid_jwt,
          "subject_token_type" => @jwt_token_type,
          "client_id" => client_id
        })

      post_token_request(token_endpoint, body)
    end
  end

  defp fetch_token_endpoint(opts) do
    name = Keyword.fetch!(opts, :name)
    worker_name = provider_worker_name(name)

    try do
      config = Oidcc.ProviderConfiguration.Worker.get_provider_configuration(worker_name)

      case config.token_endpoint do
        :undefined -> {:error, :no_token_endpoint}
        endpoint -> {:ok, endpoint}
      end
    rescue
      _ -> {:error, :idp_unreachable}
    end
  end

  def provider_worker_name(instance_name) do
    :"spiffe_ex_oidcc_#{instance_name}"
  end

  defp post_token_request(token_endpoint, body) do
    url = :binary.bin_to_list(token_endpoint)

    case :httpc.request(:post, {url, [], ~c"application/x-www-form-urlencoded", body}, [], []) do
      {:ok, {{_, 200, _}, _headers, resp_body}} ->
        parse_token_response(resp_body)

      {:ok, {{_, status, _}, _headers, resp_body}} ->
        Logger.warning("Token request failed: status=#{status} body=#{inspect(resp_body)}")
        {:error, :idp_unreachable}

      {:error, reason} ->
        Logger.warning("Token request network error: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_token_response(body) do
    bin = if is_list(body), do: IO.iodata_to_binary(body), else: body

    map =
      try do
        :jose.decode(bin)
      rescue
        _ -> nil
      end

    with %{} <- map,
         {:ok, access_token} <- Map.fetch(map, "access_token") do
      expires_at =
        case Map.get(map, "expires_in") do
          nil -> DateTime.add(DateTime.utc_now(), 3600, :second)
          secs -> DateTime.add(DateTime.utc_now(), secs, :second)
        end

      token = %SpiffeEx.Token{
        access_token: access_token,
        expires_at: expires_at,
        token_type: Map.get(map, "token_type", "Bearer"),
        scope: Map.get(map, "scope")
      }

      {:ok, token}
    else
      nil -> {:error, :invalid_token_response}
      :error -> {:error, :invalid_token_response}
    end
  end
end
