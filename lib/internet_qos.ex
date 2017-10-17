defmodule InternetQOS do
  @moduledoc """

  """
  def start( _type, _args ) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(QOS.Controller, []),
      supervisor(QOS.Method.Modem, []),
      supervisor(TackStatus.Internet, [])
    ]

    opts = [strategy: :one_for_one, name: QOS.Supervisor]
    Supervisor.start_link(children, opts)
  end

end
