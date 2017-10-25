defmodule QOS.Method.Modem do
  use GenServer

  @moduledoc """

  NOTE: This module is not saving the data to a file at this time. It is only
  capturing the data and providing it to Tack Status. Need to fix this.
  The problem is that the original code was writting for only 2 up channels but
  there can be more or less. Probably the same for the down channels. This
  needs to be expanded to allow a variable number of channels for each sample.
  Also needs to support the ability to save log records to the file. Consider
  using a defined text file format instead of a compressed binary format.

  This is a QOS method that reads status from a cable modem and places it into a timestamp data file with a specified format.

  This module is specific to the following modem and version:
  ```
  Model Name: SB6141
  Vendor Name: Motorola
  Firmware Name: SB_KOMODO-1.0.6.16-SCM00-NOSH
  Boot Version: PSPU-Boot(25CLK)(W) 1.0.12.18m5
  Hardware Version: 8.0
  Serial Number: 397185607841845801013022
  Firmware Build Time: Feb 16 2016 11:28:04
  ```

  Format of the timestamp file is as follows:
  64 bits : 64 bit timestamp with ms (UTC)

  following x 8 for upto 8 bonded downstream channels

  2 bytes : channel id (string)
  3 bytes : freq Mhz (string)
  8 bits-signed : SNR
  6 chars : modulation type
  8 bits-signed : power Level
  64 bits : unerrored codewords (uint)
  64 bits : correctable codewords (uint)
  64 bits : uncorrectable codewords (uint)

  following x 2 for upstream channels

  8 bits : channels
  8 bits : freq Mhz
  4 chars : ranging service id
  1 float : symbol rate
  8 bits-signed : power Level
  48 chars : modulation types
  10 chars : ranging status

  The methods that can be used to get and retrieve data are:

  get_qos_sample    Gets a new QOS data sample
  get_qos_data      Returns qos data for a specific period and value.
  get_qos_field_list  Returns a list of qos fields available.

  How this genserver works ...

  - On start_link, init sets a message to :sync for 2 seconds. This lets the genserver get started before the first sample will be taken.
  - A :sync message is received which is a request to get the next sample. A delay is calculated to the start of the next minute and a message to :sample is sent to arrive at that time.
  - A :sample message is received which starts the sample collection process. Collecting the sample is simply sending a tcp packet to the modem requesting the html signal page. The mode for the tcp send is active true so that packets will arrive as :tcp messages.
  - Collect :tcp message packets and place them in the genserver state.
  - When the modem is done sending the packet data, it closes the tcp channel. This results in a :tcp_closed message. When received, the packet data is processed, a sample binary generated and then written to the file. If there are any errors, they should be logged and no sample packet written. A message is then sent to :sync after 2 seconds.

  """

  @initial_state %{socket: nil, data: nil, message: []}

  def start_link do
    GenServer.start_link(__MODULE__, @initial_state, [name: ModemServer])
  end

  def init(state) do
    Process.send_after(self(), :read, 2 * 1000) # In 2 seconds start things up.
    {:ok, state}
  end

  def get_qos_data do
    GenServer.call ModemServer, :get_qos_data
  end

  def handle_call(:get_qos_data, _from, state) do
    {:reply, state.data, state}
  end

  def handle_info(:read, state) do
    Process.send_after(self(), :sync, 1000) # In 1 seconds start things up.
#    file_data = File.read!(Application.fetch_env!(:internet_qos, :modem_signal_file))

#    list =
#      for( <<
#            seconds :: unsigned-integer-size(64),
#               data :: binary-size(296) <- file_data
#           >>, do: { seconds, data} )
    {:noreply, %{ state | data: [] }}
  end

  @doc """
  Called to start a modem signal sampling cycle. The :sync state simply sets up a delay such that the :sample state will be at the start of every minute.
  """
  def handle_info(:sync, state) do

    # Figure out time to start of next minute.
    %{:second => seconds } = Timex.now
    millis_delay = (60 - seconds) * 1000
    Process.send_after(self(), :sample, millis_delay)

    # Return state.
    {:noreply, state}
  end

  @doc """
  Handles the aquisition of signal data from the modem. Data is acquired and written to the data file.
  """
  def handle_info(:sample, state) do

    # Get the sample request started.
    get_qos_sample

    # Next state will be to synchronize for the next cycle.
    Process.send_after(self(), :sync, 2 * 1000)

    {:noreply, %{state | socket: nil}}
  end

  @doc """
  Everytime a packet is received on the socket, the data is sent to this genserver method. Append the packet data to the message in the state.
  """
  def handle_info({:tcp, socket, msg}, %{message: message} = state) do
    {:noreply, %{ state | message: (message ++ [msg]) } }
  end

  @doc """
  Handles the closing of the socket. The socket is closed by the modem once the page has been delivered to the client. Parse the packet and append the data to to the data file.
  """
  def handle_info({:tcp_closed, socket}, state) do

    # Combine all packets received into a single binary.
    packet_data =
    state[:message]
    |> Enum.join

    # Parse packet and write it to disk.
    sample = get_table_data packet_data
    IO.inspect sample

#    << time :: unsigned-integer-size(64),
#       data :: binary >> = sample
#    s = {time, data}

#    data = state[:data]
#    data = data ++ [s]

    # Set state to indicate socket is closed.
    {:noreply, %{ socket: nil, message: [], data: sample}}
  end

#internet_qos bengm0ra$ iex --name one@10.0.1.21 --cookie monster -S mix
#GenServer.call({ModemServer, :'one@10.0.1.21'}, {:retrieve, "Hi!"})
  def handle_call({:retrieve}, from, state) do
    IO.puts "Received :retrieve message"

    {:reply, {:ok, state[:data]}, state}
  end

  # Collects a sample of data from the cable modem.
  # Connects to the modem and issues a get for the signal data page.
  defp get_qos_sample do

    # Open TCP Connection and send the request.
    opts = [:binary, active: true]
    request = "GET /cmSignalData.htm HTTP/1.0\r\nHost: 192.168.100.1:80\r\n\r\n"

    with  {:ok, socket} <- :gen_tcp.connect('192.168.100.1', 80, opts),
                    :ok <- :gen_tcp.send(socket,request)
    do
      {:ok, socket}
    else
      err                 -> err
    end
  end

  # Special handling for the modem signal page. Several things are being done
  # in this function:
  #
  #   1 - Floki returns 4 tables since there's a nested table in the Downstream
  #       table. It's the second table so remove it.
  #   2 - The nested table in Downstream table is still in the Downstream table
  #       so it needs to be removed.
  #       It's simply putting additional text in the column description for
  #       the Power Level row. It's removal makes step 2 easier.
  #   3 - Return a list of all table values. There are 102 <td>'s after step 1
  #       and this returns all those values.
  defp get_table_data packet_data do

    # Remove the nested table from the table list. Note it's still in the first
    # table.
    html = Floki.find(packet_data,"table")
    html = List.delete_at(html,1)
#    IO.inspect {:html, html}

    # Removes the nested table in the Downstream table.
    pre_traversal = fn node, acc ->
      case node do
        {"td",[],["Power Level" | tail]} ->
          { {"td",[],["Power Level"]}, acc}
        _ -> {node, acc}
      end
    end

    # Accumulates a list of all the table data values.
    post_traversal = fn node, acc ->
      case node do
        {"td",[],[value | tail]} ->
          {node, acc ++ [value]}
        _ -> {node, acc}
      end
    end

    # Traverse the html to get the table data.
    {_, table_data} = Macro.traverse(html,[],pre_traversal,post_traversal)

#    IO.inspect {:table_data, table_data}

    [t1, t2, t3] = find_table_starts table_data
    length = table_data |> Enum.count
#    IO.inspect {:table_starts, t1, t2, t3, length}
    indicies = {t1, t2, t3, length}

    metrics = get_metrics table_data, indicies
    IO.inspect {:metrics, metrics}

    # Table data is now as follows based on list position:
    #
    #     [0..44] - Table 1 : Downstream Channel Signals
    #     [45..65] - Table 2 : Upstream Channel Signals
    #     [66..101] - Table 3 : Downstream Codeword data
    #
    # Separate Upstream table.
    # Combine two Downstream tables.

#    upstream_data = table_data |> Enum.slice 45..65
#    IO.inspect {:upstream, upstream_data}
#    downstream_data =
#      (table_data |> Enum.slice 0..44)
#      ++
#      (table_data |> Enum.slice 75..102)
#    generate_downstream_sample_string downstream_data
    metrics
  end

  defp get_metrics table, {t1, t2, t3, ln} do

    t1_chans = div((t2-t1), 5) - 1
    t2_chans = div((t3-t2), 7) - 1
    t3_chans = div((ln-t3), 4) - 1

#    IO.inspect {:chan_count, t1_chans, t2_chans, t3_chans}

    dn_power =
      table
      |> Enum.drop(4*(t1_chans+1)+1)
      |> Enum.take(t1_chans)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.split(&1, " "))
      |> Enum.map(fn [pw,_] -> Integer.parse(pw) |> elem(0) end)

    dn_ave = (dn_power |> Enum.sum) / t1_chans
#    IO.inspect {:dn_ave, dn_ave}
    dn_std =
      dn_power
      |> Enum.map(fn p -> (p - dn_ave) * (p - dn_ave) end)
      |> Enum.sum
    dn_std = :math.sqrt(dn_std / t1_chans)

    up_power =
      table
      |> Enum.slice(t2..t3-1)
      |> Enum.drop(4*(t2_chans+1)+1)
      |> Enum.take(t2_chans)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.split(&1, " "))
      |> Enum.map(fn [pw,_] -> Integer.parse(pw) |> elem(0) end)

    up_ave = (up_power |> Enum.sum) / t2_chans
#    IO.inspect {:up_ave, up_ave}
    up_std =
      up_power
      |> Enum.map(fn p -> (p - up_ave) * (p - up_ave) end)
      |> Enum.sum
    up_std = :math.sqrt(up_std / t1_chans)
#    IO.inspect {:up_std, up_std}

    %{
      dn_chans: t1_chans, dn_ave: dn_ave, dn_std: dn_std,
      up_chans: t2_chans, up_ave: up_ave, up_std: up_std
    }

  end

  # Finds the list entry numbers for cells with "Channel ID". There should
  # be 3 of these. Indexes returned are zero based.
  defp find_table_starts data do
    data
    |> Enum.with_index
    |> Enum.filter( fn {v, i} -> v == "Channel ID" end)
    |> Enum.map( fn {v, i} -> i end)
  end

  @doc """
  Returns a timestamped sample of downstream signal data. Format is specified above.
  """
  def generate_downstream_sample_string data do

    sample =
      1..8
      |> Enum.map(&(element_channel_data(&1,data)))
      |> Enum.join

      sample = element_timestamp <> sample

      save_results sample

      sample
  end

  def element_timestamp do
    { megaseconds, seconds, microseconds } =  :erlang.timestamp
    seconds_stamp = (megaseconds * 1000000 + seconds)
    << seconds_stamp :: unsigned-integer-size(64) >>
  end

  def element_channel_data(channel, data) do
    data
    |> Enum.drop(channel)
    |> Enum.take_every(9)
    |> element_channel_encode
  end

  def element_channel_encode(data) do
    [chan,freq,snr,mod,power,words,correct,error] = data

    chan = chan |> String.trim |> String.pad_leading(2,"00")
    freq = freq |> String.trim |> String.slice(0,3)
    { snr, _ }  = snr  |> String.trim |> Integer.parse
    modu = mod  |> String.trim |> String.pad_trailing(6)
    { powr, _ } = power |> String.trim |> Integer.parse
    { words, _ } = words |> String.trim |> Integer.parse
    { correct, _ } = correct |> String.trim |> Integer.parse
    { error, _ } = error |> String.trim |> Integer.parse

    <<
      chan :: binary-size(2),
      freq :: binary-size(3),
      snr :: signed-integer-size(8),
      modu :: binary-size(6),
      powr :: signed-integer-size(8),
      words :: unsigned-integer-size(64),
      correct :: unsigned-integer-size(64),
      error :: unsigned-integer-size(64)
    >>
  end

  def save_results(data) do
    filepath = Application.fetch_env!(:internet_qos, :modem_signal_file)
      {:ok, file} = File.open filepath, [:append]
      IO.binwrite(file, data)
      File.close file
  end
end
