# InternetQOS

Monitors home internet access using several methods. Provides channels for alerts and charting showing current and historical quality of service.

Methods for measuring internet quality of service are:

- Upstream / Downstream Signal Levels Reported By Cable Modem
- Ping Times To One Or More Internet Servers

Possible QOS methods that could be added:

- File Upload / Download Speed Checks

Data from the measuring methods are stored in one or more files with an associated timestamp. Full definition for the file needs to be specified.

## To Do List

- Figure out how to periodically sample each module.
- Have modem module do a timeout and set a null packet.
- Have modem module do a get at 0 seconds of each minute.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `internet_qos` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:internet_qos, "~> 0.1.0"}]
    end
    ```

  2. Ensure `internet_qos` is started before your application:

    ```elixir
    def application do
      [applications: [:internet_qos]]
    end
    ```
