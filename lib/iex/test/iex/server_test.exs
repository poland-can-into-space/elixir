Code.require_file("../test_helper.exs", __DIR__)

defmodule IEx.ServerTest do
  use IEx.Case

  require IEx

  describe "options" do
    test "prefix" do
      assert capture_io(fn ->
               boot(prefix: "pry")
             end) =~ "pry(1)> "
    end

    test "env" do
      assert capture_io("__ENV__.file", fn ->
               boot(env: __ENV__)
             end) =~ "server_test.exs"
    end
  end

  # describe "take_over during boot" do
  #   test "works successfully" do
  #     assert capture_io("Y\na+b", fn ->
  #              server = self()

  #              boot([], fn ->
  #                opts = [prefix: "dbg", binding: [a: 1, b: 2]]
  #                IEx.Server.take_over("iex:13", opts, server)
  #              end)
  #            end) =~ "dbg(1)> "
  #   end

  #   test "continues if takeover is refused" do
  #     assert capture_io("N\n", fn ->
  #              server = self()

  #              boot([], fn ->
  #                opts = [prefix: "dbg", binding: [a: 1, b: 2]]
  #                IEx.Server.take_over("iex:13", opts, server)
  #              end)
  #            end) =~ "iex(1)> "
  #   end

  #   test "fails if take over callback fails" do
  #     assert capture_io(fn ->
  #              boot([], fn -> exit(0) end)
  #            end) == ""
  #   end

  #   test "fails when there is no shell" do
  #     assert IEx.Server.take_over("iex:13", []) == {:error, :no_iex}
  #   end
  # end

  describe "pry" do
    test "outside IEx" do
      assert capture_io(fn ->
               require IEx
               assert IEx.pry() == {:error, :no_iex}
             end) =~ "Is an IEx shell running?"
    end

    test "inside evaluator itself" do
      assert capture_iex("require IEx; IEx.pry") =~ "Break reached"
    end

    test "outside of the evaluator with acceptance", config do
      Process.register(self(), config.test)

      server = pry_session(config.test, :Y, "iex_context")
      client = pry_request()
      send(server.pid, :run)

      assert Task.await(server) =~ ":inside_pry"
      assert Task.await(client) == :ok
    end

    test "outside of the evaluator with refusal", config do
      Process.register(self(), config.test)

      server = pry_session(config.test, :N, "")
      client = pry_request()
      send(server.pid, :run)
      assert Task.await(client) == {:error, :refused}
      _ = Task.shutdown(server, :brutal_kill)
    end
  end

  # Helpers

  defp pry_session(name, confirmation, session) do
    task =
      Task.async(fn ->
        capture_iex("""
        send(#{inspect(name)}, :running)
        receive do: (:run -> :ok)
        #{confirmation}
        #{session}
        """)
      end)

    assert_receive :running
    task
  end

  defp pry_request() do
    :erlang.trace(:new_processes, true, [:call, tracer: self()])
    :erlang.trace_pattern({IEx.Broker, :take_over, :_}, [])

    task =
      Task.async(fn ->
        iex_context = :inside_pry
        IEx.pry()
      end)

    assert_receive {:trace, _, :call, _}
    task
  end

  defp boot(opts, callback \\ fn -> nil end) do
    IEx.Server.shell_start(
      Keyword.merge([dot_iex_path: ""], opts),
      {:erlang, :apply, [callback, []]}
    )
  end
end
