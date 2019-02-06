defmodule TackStatus.Internet do
  use GenServer

  defmodule Status do
    defstruct [:name, :icon, :status, :state, :link, :hover, :metrics, :text]
  end

  defmodule Metric do
    defstruct [:name, :value]
  end

  # --------- GenServer Startup Functions

  @doc """
  Starts the GenServer. This of course calls init with the :ok parameter.
  """
  def start_link do
    {:ok, _} = GenServer.start_link(__MODULE__, :ok, name: StatusServer)
  end

  @doc """
  Read the rain data file and generate the list of rain gauge tips. This
  is held in the state as tips. tip_inches is amount of rain for each tip.
  """
  def init(:ok) do
    [host: host, port: port, start: _start] =
      Application.fetch_env!(:internet_qos, :status_server)

    start()
    datetime = Timex.now("America/Chicago")
    {:ok, %{parms: %{host: host, port: port, started: datetime}, server: %{}, client: %{}}}
  end

  def start do
    spawn(__MODULE__, :update_status, [])
  end

  # ------------ Tack Status
  def update_status do
    Process.sleep(10000)
    send_status()
    update_status()
  end

  def send_status do
    data = QOS.Method.Modem.get_qos_data()

    ver_commit = Mix.Project.config()[:version] <> " " <> QOS.Method.Modem.commit()
    commit_metric = %Metric{name: "Version Commit", value: ver_commit}

    metrics = [commit_metric] ++ set_metrics(data)

    stat = %Status{
      name: "Internet Status",
      icon: get_icon("project/graphics/world.png"),
      status: "Internet QOS Running",
      metrics: metrics,
      state: :nominal,
      link: "http://192.168.100.1/cmSignalData.htm"
    }

    with {:ok, packet} <- Poison.encode(stat),
         {:ok, socket} <- :gen_tcp.connect('10.0.1.181', 21200, [:binary, active: false]),
         _send_ret <- :gen_tcp.send(socket, packet),
         _close_ret <- :gen_tcp.close(socket) do
      nil
    else
      _ -> nil
    end
  end

  def set_metrics([]) do
    [
      %Metric{name: "Down Channels (\#/μ/σ)", value: "No Data"},
      %Metric{name: "Up Channels (\#/μ/σ)", value: "No Data"}
    ]
  end

  def set_metrics(data) do
    #    IO.inspect({:status_data, data})
    #    IO.inspect {:sending_status}

    dn_ave = String.trim(to_string(:io_lib.format("~10.2f", [data[:dn_ave]])))
    dn_std = String.trim(to_string(:io_lib.format("~10.2f", [data[:dn_std]])))
    up_ave = String.trim(to_string(:io_lib.format("~10.2f", [data[:up_ave]])))
    up_std = String.trim(to_string(:io_lib.format("~10.2f", [data[:up_std]])))

    dn_mets = "#{data[:dn_chans]}/#{dn_ave}/#{dn_std}"
    up_mets = "#{data[:up_chans]}/#{up_ave}/#{up_std}"

    [
      %Metric{name: "Down Channels (\#/μ/σ)", value: dn_mets},
      %Metric{name: "Up Channels (\#/μ/σ)", value: up_mets}
    ]
  end

  def get_icon(path) do
    {:ok, icon} = File.read(path)
    icon = Base.encode64(icon)
    icon
  end
end
