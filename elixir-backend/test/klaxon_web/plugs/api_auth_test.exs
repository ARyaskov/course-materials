defmodule KlaxonWeb.Plugs.ApiAuthTest do
  use Klaxon.DataCase, async: true

  import Plug.Test
  import Plug.Conn

  alias Klaxon.Accounts.ApiKey
  alias KlaxonWeb.Plugs.ApiAuth

  # Опции инициализируются один раз — так же, как это делает Plug.Builder
  # при компиляции конвейера.
  @opts ApiAuth.init([])

  test "кладёт scope в assigns при корректном ключе" do
    organization = organization_fixture()
    {_api_key, token} = api_key_fixture(organization)

    conn =
      :post
      |> conn("/api/v1/signals")
      |> put_req_header("authorization", "Bearer " <> token)
      |> ApiAuth.call(@opts)

    refute conn.halted
    assert conn.assigns.scope.organization.id == organization.id
  end

  test "принимает схему в нижнем регистре" do
    organization = organization_fixture()
    {_api_key, token} = api_key_fixture(organization)

    conn =
      :post
      |> conn("/api/v1/signals")
      |> put_req_header("authorization", "bearer " <> token)
      |> ApiAuth.call(@opts)

    refute conn.halted
  end

  test "отвечает 401 без заголовка" do
    conn = :post |> conn("/api/v1/signals") |> ApiAuth.call(@opts)

    assert conn.halted
    assert conn.status == 401
    assert %{"error" => %{"code" => "unauthorized"}} = Jason.decode!(conn.resp_body)
    assert [~s(Bearer realm="klaxon")] = get_resp_header(conn, "www-authenticate")
  end

  test "отвечает 401 при неизвестном ключе" do
    conn =
      :post
      |> conn("/api/v1/signals")
      |> put_req_header("authorization", "Bearer klx_несуществующий")
      |> ApiAuth.call(@opts)

    assert conn.status == 401
  end

  test "отвечает 401 при отозванном ключе" do
    organization = organization_fixture()
    {api_key, token} = api_key_fixture(organization)

    api_key |> ApiKey.revoke_changeset() |> Repo.update!()

    conn =
      :post
      |> conn("/api/v1/signals")
      |> put_req_header("authorization", "Bearer " <> token)
      |> ApiAuth.call(@opts)

    assert conn.status == 401
  end

  test "отвечает 401 при просроченном ключе" do
    organization = organization_fixture()

    {:ok, api_key, token} =
      Klaxon.Accounts.create_api_key_for_organization(organization, %{
        "name" => "expired",
        "role" => "viewer"
      })

    api_key
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    conn =
      :post
      |> conn("/api/v1/signals")
      |> put_req_header("authorization", "Bearer " <> token)
      |> ApiAuth.call(@opts)

    assert conn.status == 401
    assert %{"error" => %{"details" => %{"reason" => reason}}} = Jason.decode!(conn.resp_body)
    assert reason =~ "отозван или просрочен"
  end
end
