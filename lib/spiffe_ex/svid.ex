defmodule SpiffeEx.SVID do
  @enforce_keys [:token, :spiffe_id, :expires_at]
  defstruct [:token, :spiffe_id, :expires_at]

  @type t :: %__MODULE__{
          token: String.t(),
          spiffe_id: String.t(),
          expires_at: DateTime.t()
        }
end
