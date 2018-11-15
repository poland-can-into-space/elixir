defmodule IEx.Broker do
  @moduledoc false
  @name IEx.Broker

  # TODO: docs
  # TODO: what happens if a session crash during take over
  # TODO: Move IEx.State.whereis here
  # TODO: What happens if somebody accepts and another refuses
  # TODO: What happens if somebody refuses and another accepts
  # TODO: What happens if two accept
  # TODO: What happens if two refuse

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  def register(pid) do
    GenServer.call(@name, {:register, pid})
  end

  @spec take_over(binary, keyword) :: {:ok, pid, pid} | {:error, :no_iex} | {:error, :refused}
  def take_over(identifier, opts) do
    GenServer.call(@name, {:take_over, identifier, opts}, :infinity)
  end

  ## Callbacks

  def init(:ok) do
    state = %{
      servers: %{},
      takeovers: %{}
    }

    {:ok, state}
  end

  # TODO: Consider local shells during take over

  def handle_call({:take_over, identifier, opts}, {_, ref} = from, state) do
    case servers(state) do
      [] ->
        {:reply, {:error, :no_iex}, state}

      servers ->
        server_refs =
          for {server_ref, server_pid} <- servers do
            send(server_pid, {:take_over, self(), identifier, {ref, server_ref}, opts})
            server_ref
          end

        state = put_in(state.takeovers[ref], {from, server_refs})
        {:noreply, state}
    end
  end

  def handle_call({:register, pid}, _from, state) do
    ref = Process.monitor(pid)
    state = put_in(state.servers[ref], pid)
    {:reply, :ok, state}
  end

  def handle_info({:DOWN, ref, _, _, _}, state) do
    {_pid, state} = pop_in(state.servers[ref])
    {:noreply, state}
  end

  def handle_info({:accept, {ref, _server_ref}, server, leader}, state) do
    {{from, _}, state} = pop_in(state.takeovers[ref])
    GenServer.reply(from, {:ok, server, leader})
    {:noreply, state}
  end

  def handle_info({:refuse, {ref, server_ref}}, state) do
    {from, server_refs} = state.takeovers[ref]

    case List.delete(server_refs, server_ref) do
      [] ->
        {_, state} = pop_in(state.takeovers[ref])
        GenServer.reply(from, {:error, :refused})
        {:noreply, state}

      server_refs ->
        state = put_in(state.takeovers[ref], {from, server_refs})
        {:noreply, state}
    end
  end

  defp servers(state) do
    if pid = IEx.Server.whereis do
      [{Process.monitor(pid), pid} | Enum.to_list(state.servers)]
    else
      Enum.to_list(state.servers)
    end
  end
end
