defmodule Roger.AppCase do
  use ExUnit.CaseTemplate

  using(opts) do
    quote do

      require Logger
      alias Roger.{Application, Queue, Job}

      setup do
        Process.register(self(), :testcase)
        app = %Application{id: "test", queues: [Queue.define(:default, 10)]}
        {:ok, _pid} = Application.start(app)

        Elixir.Application.put_env(:roger, :callbacks, unquote(opts)[:callbacks] || [])

        on_exit fn ->
          Elixir.Application.put_env(:roger, :callbacks, [])
        end

        {:ok, %{app: app}}
      end

    end
  end
end
