defmodule Rollbax.ClientTest do
  use ExUnit.RollbaxCase

  alias Rollbax.Client

  setup_all do
    {:ok, pid} = start_rollbax_client("token1", "test", %{qux: "custom"})
    on_exit(fn ->
      ensure_rollbax_client_down(pid)
    end)
  end

  setup do
    {:ok, _} = RollbarAPI.start(self())
    on_exit(&RollbarAPI.stop/0)
  end

  test "emit/5" do
    custom = %{foo: "bar"}
    :ok = Client.emit(:warn, unix_time(), %{"message" => %{"body" => "pass"}}, custom, %{})
    assert_receive {:api_request, body}
    assert %{
      "access_token" => "token1",
      "data" => %{
        "body" => %{
          "message" => %{
            "body" => "pass"
          }
        },
        "custom" => %{
          "foo" => "bar",
          "qux" => "custom"
        },
        "environment" => "test",
        "level" => "warn"
      }
    } = Poison.decode!(body)
  end

  test "emit/5: custom values should take precendence over global ones" do
    custom = %{qux: "overridden", quux: "another"}
    :ok = Client.emit(:warn, unix_time(), %{"message" => %{"body" => "pass"}}, custom, %{})
    assert_receive {:api_request, body}
    assert %{
     "data" => %{
      "custom" => %{
        "qux" => "overridden",
        "quux" => "another"
      },
    }} = Poison.decode!(body)
  end

  test "mass sending" do
    for _ <- 1..60 do
      :ok = Client.emit(:error, unix_time(), %{"message" => %{"body" => "pass"}}, %{}, %{})
    end

    for _ <- 1..60 do
      assert_receive {:api_request, _body}
    end
  end

  test "endpoint is down" do
    :ok = RollbarAPI.stop
    log = capture_log(fn ->
      :ok = Client.emit(:error, unix_time(), %{"message" => %{"body" => "miss"}}, %{}, %{})
    end)
    assert log =~ "[error] (Rollbax) connection error: :econnrefused"
    refute_receive {:api_request, _body}
  end

  test "errors from the API are logged" do
    log = capture_log(fn ->
      :ok = Client.emit(:error, unix_time(), %{}, %{return_error?: true}, %{})
      assert_receive {:api_request, _body}
    end)

    assert log =~ ~s{[error] (Rollbax) unexpected API status: 400}
    assert log =~ ~s{[error] (Rollbax) API returned an error: "that was a bad request"}
  end

  defp unix_time() do
    {mgsec, sec, _usec} = :os.timestamp()
    mgsec * 1_000_000 + sec
  end
end
