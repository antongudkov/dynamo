defmodule Dynamo.HTTP.Hibernate do
  @moduledoc """
  Conveniences that allows a connection to hibernate or
  wait a given amount or an unlimited amount of time.
  Such conveniences are useful when a connection needs
  to be kept open (because of long polling, websockets
  or streaming) but you don't want to keep the current
  erlang process active all times and waiting through
  small intervals or hibernating through long intervals
  is convenient.
  """

  @key :__timeref__

  @doc """
  Hibernates the current process until a message is received.
  The `on_wake_up` callback is invoked with the `conn` and the
  received message on wake up.

  For more information on hibernation, check:
  http://www.erlang.org/doc/man/erlang.html#hibernate-3
  """
  def hibernate(conn, on_wake_up) when is_function(on_wake_up, 2) do
    clear_timeout(conn)
    :erlang.hibernate(__MODULE__, :__loop__, [conn, on_wake_up, :no_timeout_callback])
  end

  @doc """
  Hibernates the current process until a message is received
  but also sets a timeout for hibernation time.

  The `on_wake_up` callback is invoked with the `conn` and the
  received message on wake up. A `on_timeout` callback is
  invoked when it times out.

  For more information on hibernation, check:
  http://www.erlang.org/doc/man/erlang.html#hibernate-3
  """
  def hibernate(conn, timeout, on_wake_up, on_timeout) when is_integer(timeout) and
      is_function(on_wake_up, 2) and is_function(on_timeout, 1) do
    clear_timeout(conn)
    conn = set_timeout(conn, timeout)
    :erlang.hibernate(__MODULE__, :__loop__, [conn, on_wake_up, on_timeout])
  end

  @doc """
  Sleeps the current process until a message is received.
  The `on_wake_up` callback is invoked with the `conn` and the
  received message on wake up.
  """
  def await(conn, on_wake_up) when is_function(on_wake_up, 2) do
    clear_timeout(conn)
    __loop__(conn, on_wake_up, :no_timeout_callback)
  end

  @doc """
  Sleeps the current process until a message is received
  but also sets a timeout for hibernation time.

  The `on_wake_up` callback is invoked with the `conn` and the
  received message on wake up. A `on_timeout` callback is
  invoked when it times out.
  """
  def await(conn, timeout, on_wake_up, on_timeout) when is_integer(timeout) and
      is_function(on_wake_up, 2) and is_function(on_timeout, 1) do
    clear_timeout(conn)
    conn = set_timeout(conn, timeout)
    __loop__(conn, on_wake_up, on_timeout)
  end

  @doc false
  def __loop__(conn, on_wake_up, on_timeout) do
    ref = conn.assigns[@key]
    receive do
      { :timeout, ^ref, __MODULE__ } ->
        on_timeout.(conn)
      { :timeout, older_ref, __MODULE__ } when is_reference(older_ref) ->
        __loop__(conn, on_wake_up, on_timeout)
      msg ->
        on_wake_up.(conn, msg)
    end
  end

  defp clear_timeout(conn) do
    ref = conn.assigns[@key]
    ref && :erlang.cancel_timer(ref)
  end

  defp set_timeout(conn, timeout) do
    ref = :erlang.start_timer(timeout, self(), __MODULE__)
    conn.assign(@key, ref)
  end
end