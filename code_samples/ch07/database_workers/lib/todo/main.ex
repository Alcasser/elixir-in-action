defmodule Todo.Main do
  def main do
    {:ok, cache} = Todo.Cache.start()
    aserver = Todo.Cache.server_process(cache, "A")
    Todo.Server.add_entry(aserver, %{name: "Learn Elixir", date: "10/10/2020"})
  end

  def read do
    {:ok, cache} = Todo.Cache.start()
    aserver = Todo.Cache.server_process(cache, "A")
    Todo.Server.entries(aserver, "10/10/2020")
  end
end
