defmodule Todo.Database do
  use GenServer

  @db_folder "./persist"

  def start do
    GenServer.start(__MODULE__, nil, name: __MODULE__)
  end

  def store(key, data) do
    GenServer.cast(__MODULE__, {:store, key, data})
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  @impl GenServer
  def init(_) do
    File.mkdir_p!(@db_folder)
    {:ok, nil}
  end

  @impl GenServer
  def handle_cast({:store, key, data}, state) do
    key
    |> file_name()
    |> File.write!(:erlang.term_to_binary(data))

    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:get, key}, _, state) do
    data =
      case File.read(file_name(key)) do
        {:ok, contents} -> :erlang.binary_to_term(contents)
        _ -> nil
      end

    {:reply, data, state}
  end

  defp file_name(key) do
    Path.join(@db_folder, to_string(key))
  end
end

defmodule Todo.ConcurrentDatabase do
  use GenServer

  def start do
    GenServer.start(__MODULE__, nil, name: __MODULE__)
  end

  def store(name, %Todo.List{} = data) do
    name
    |> choose_worker()
    |> Todo.DatabaseWorker.store(name, data)
  end

  def get(name) do
    name
    |> choose_worker()
    |> Todo.DatabaseWorker.get(name)
  end

  defp choose_worker(name) do
    GenServer.call(__MODULE__, {:choose_worker, name})
  end

  @impl GenServer
  def init(_) do
    workers = for index <- 1..3, into: %{} do
      {:ok, pid} = Todo.DatabaseWorker.start()
      {index - 1, pid}
    end
    {:ok, workers}
  end

  @impl GenServer
  def handle_call({:choose_worker, key}, _, workers) do
    worker_key = :erlang.phash2(key, 3)
    {:reply, Map.get(workers, worker_key), workers}
  end
end

defmodule Todo.DatabaseWorker do
  use GenServer

  def start do
    GenServer.start(__MODULE__, nil)
  end

  def store(worker, name, %Todo.List{} = data) do
    GenServer.cast(worker, {:store, name, data})
  end

  def get(worker, name) do
    GenServer.call(worker, {:get, name})
  end

  @impl GenServer
  def init(_) do
    [pid_number | _] = Regex.run(~r/(\.|\d)+/, inspect self())
    {:ok, conn} = Exqlite.Sqlite3.open("file:data_#{pid_number}.db")
    case Exqlite.Sqlite3.execute(conn, "create table persist (id integer primary key, name text, data text)") do
      _ -> nil
    end
    {:ok, conn}
  end

  @impl GenServer
  def handle_cast({:store, name, data}, conn) do
    bin_data = :erlang.term_to_binary(data)

    {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "insert into persist (name,data) values (?1,?2)")
    :ok = Exqlite.Sqlite3.bind(conn, statement, [name, bin_data])
    :done = Exqlite.Sqlite3.step(conn, statement)

    {:noreply, conn}
  end

  @impl GenServer
  def handle_call({:get, name}, _, conn) do
    {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "select data from persist where name=?1")
    :ok = Exqlite.Sqlite3.bind(conn, statement, [name])

    elems = read_elems(conn, statement, [])
    elems = Enum.map(elems, fn elem_data -> :erlang.binary_to_term(elem_data) end)

    {:reply, elems, conn}
  end

  defp read_elems(conn, statement, elems) do
    case Exqlite.Sqlite3.step(conn, statement) do
      {:row, [data]} -> read_elems(conn, statement, [data | elems])
      :done -> elems
    end
  end
end

