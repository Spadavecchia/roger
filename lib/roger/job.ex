defmodule Roger.Job do
  @moduledoc """
  Base module for implementing Roger jobs.

  To start, `use Roger.Job` in your module. The only required callback
  to implement is the `perform/1` function.

  Other functions that can be implemented in a job module are the
  following:

  `queue_key/1` - Enforces job uniqueness. When returning a string
  from this function, Roger enforces that only one job per queue key
  can be put in the queue at the same time. Only when the job has left
  the queue (after it has been executed), it will be possible to
  enqueue a job with the same queue key again.

  `execution_key/1` - Enforces job execution serialization. When
  returning a string from this function, Roger enforces that not more
  than one job with the same job is executed concurrently. However, it
  is still possible to have multiple jobs with the same execution key
  enqueued, but jobs that have the same execution key will be put in a
  waiting queue and processed serially.

  `queue_type/1` - Specifies which application queue the job will run
  on. By default, this function returns `:default`, the default queue
  type.

  `retryable?/0` - Specifies whether the job should be retried using
  an exponential backoff scheme. The default implementation returns
  false, meaning that jobs will not be retried.

  """

  @type t :: %__MODULE__{}

  @derive {Poison.Encoder, only: ~w(id module args queue_key execution_key retry_count)a}
  defstruct id: nil, module: nil, args: nil, queue_key: nil, execution_key: nil, retry_count: 0, started_at: 0, queued_at: 0

  alias Roger.{Application, Queue, Application.Global, Job}

  require Logger

  @content_type "application/x-erlang-binary"

  @doc """
  Enqueues a job in the given application.
  """
  def enqueue(%__MODULE__{} = job, application_id, override_queue \\ nil) do
    queue = Queue.make_name(application_id, override_queue || queue_type(job))

    # Check the queue key; when there is a queue key and it is not
    # queued, immediately add it to the queue key set to prevent
    # races.
    if job.queue_key != nil and Global.queued?(application_id, job.queue_key, :add) do
      {:error, :duplicate}
    else
      job = %Job{job | queued_at: Roger.now}
      Roger.AMQPClient.publish("", queue, encode(job), Job.publish_opts(job, application_id))
    end
  end

  @doc """
  Constructs the AMQP options for publishing the job
  """
  def publish_opts(%__MODULE__{} = job, application_id) do
    [content_type: @content_type,
     persistent: true,
     message_id: job.id,
     app_id: application_id]
  end

  @doc false
  defmacro __using__(_) do

    quote do
      @after_compile __MODULE__

      def queue_key(_args), do: nil
      def execution_key(_args), do: nil
      def queue_type(_args), do: :default
      def retryable?(), do: false

      defoverridable queue_key: 1, execution_key: 1, queue_type: 1, retryable?: 0

      def __after_compile__(env, _) do
        if !Module.defines?(__MODULE__, {:perform, 1}) do
          raise ArgumentError, "#{__MODULE__} must implement the perform/1 function"
        end
      end

    end
  end

  @callback queue_key(any) :: String.t
  @callback execution_key(any) :: String.t
  @callback queue_type(any) :: atom
  @callback perform(any) :: any

  @doc """
  Creates a new job based on a job module.

  The given `module` must exist as an Elixir module and must be
  implementing the Job behaviour (`use Roger.Job`).

  The function returns the Job struct, which can be sent off to the
  queues using `Job.enqueue/2`.
  """
  def create(module, args \\ [], id \\ nil) when is_atom(module) do
    keys =
      ~w(queue_key execution_key)a
      |> Enum.map(fn(prop) -> {prop, Kernel.apply(module, prop, [args])} end)
      |> Enum.into(%{})

    %__MODULE__{module: module, args: args, id: id || generate_job_id()}
    |> Map.merge(keys)
    |> validate
  end

  defp generate_job_id do
    :crypto.rand_bytes(20) |> Base.hex_encode32(case: :lower)
  end

  @doc """
  Executes the given job.

  This function is called from within a `Job.Worker` process, there's
  no need to call it yourself.
  """
  def execute(%__MODULE__{} = job) do
    Kernel.apply(job.module, :perform, [job.args])
  end

  @doc """
  Decode a binary payload into a Job struct, and validates it.
  """
  @spec decode(String.t) :: Roger.Job.t
  def decode(payload) do
    (try do
       {:ok, :erlang.binary_to_term(payload)}
     rescue
       ArgumentError ->
         {:error, "Job decoding error"}
     end)
     |> validate
  end

  def encode(job) do
    job |> :erlang.term_to_binary
  end

  defp validate({:ok, job}), do: validate(job)
  defp validate({:error, _} = e), do: e

  defp validate(%__MODULE__{id: id}) when not(is_binary(id)) do
    {:error, "Job id must be set"}
  end

  defp validate(%__MODULE__{module: module}) when not(is_atom(module)) do
    {:error, "Job module must be an atom"}
  end

  defp validate(%__MODULE__{module: module} = job) do
    case :code.ensure_loaded(module) do
      {:error, :nofile} ->
        {:error, "Unknown job module: #{module}"}
      {:module, ^module} ->
        functions = module.__info__(:functions)
        case Enum.member?(functions, {:perform, 1}) do
          false ->
            {:error, "Invalid job module: #{module} does not implement Roger.Job"}
          true ->
            {:ok, job}
        end
    end
  end

  def queue_type(%__MODULE__{} = job) do
    job.module.queue_type(job.args)
  end

  def retryable?(%__MODULE__{} = job) do
    job.module.retryable?()
  end

end
