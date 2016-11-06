defmodule QOS.Method.Modem do
  use GenServer

  @moduledoc """
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

  @initial_state %{socket: nil, message: []}

  def start_link do
    GenServer.start_link(__MODULE__, @initial_state)
  end

  def init(state) do
    Process.send_after(self(), :sync, 2 * 1000) # In 2 seconds start things up.
    {:ok, state}
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
    {:ok, socket} = get_qos_sample

    # Next state will be to synchronize for the next cycle.
    Process.send_after(self(), :sync, 2 * 1000)

    {:noreply, %{state | socket: socket}}
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
    get_table_data packet_data

    # Set state to indicate socket is closed.
    {:noreply, %{ socket: nil, message: []}}
  end

  @doc """
  Collects a sample of data from the cable modem.
  """
  def get_qos_sample do

    # Open TCP Connection
    opts = [:binary, active: true]
    {:ok, socket} = :gen_tcp.connect('192.168.100.1', 80, opts)

    # Make request to modem for signal data.
    request = "GET /cmSignalData.htm HTTP/1.0\r\nHost: 192.168.100.1:80\r\n\r\n"
    :ok = :gen_tcp.send(socket,request)

    # Return status and the socket reference.
    {:ok, socket}
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

    # Table data is now as follows based on list position:
    #
    #     [0..44] - Table 1 : Downstream Channel Signals
    #     [45..65] - Table 2 : Upstream Channel Signals
    #     [66..101] - Table 3 : Downstream Codeword data
    #
    # Separate Upstream table.
    # Combine two Downstream tables.

    upstream_data = table_data |> Enum.slice 45..65
    downstream_data =
      (table_data |> Enum.slice 0..44)
      ++
      (table_data |> Enum.slice 75..102)
    generate_downstream_sample_string downstream_data
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
    millis_stamp = (megaseconds * 1000000 + seconds) * 1000 + div(microseconds,1000)
    << millis_stamp :: unsigned-integer-size(64) >>
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
