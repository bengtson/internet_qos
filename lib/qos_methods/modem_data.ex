defmodule QOS.Method.ModemData do
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

  @doc """
  """
  def filter_modem_data(data, start_date, stop_date) do

  end

  def filter_modem_data(data, last_days) do

  end

  def get_downstream_channel_list data do
    data
    |> Enum.map(fn sample ->
        << seconds :: unsigned-integer-size(64),
           rest :: binary >> = sample
            seconds end)

  end

  def get_channel_metric(metric) do

  end

end
