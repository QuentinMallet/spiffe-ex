defmodule SpiffeEx.Generators do
  use ExUnitProperties

  def svid_ttl_seconds, do: integer(30..3600)
  def refresh_buffer_seconds, do: integer(5..25)

  def audience_list,
    do: list_of(string(:alphanumeric, min_length: 3), min_length: 1, max_length: 3)

  def concurrent_caller_count, do: integer(2..20)
end
