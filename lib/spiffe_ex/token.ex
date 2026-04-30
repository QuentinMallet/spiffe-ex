defmodule SpiffeEx.Token do
  @enforce_keys [:access_token, :expires_at]
  defstruct [:access_token, :expires_at, :token_type, :scope]

  @type t :: %__MODULE__{
          access_token: String.t(),
          expires_at: DateTime.t(),
          token_type: String.t(),
          scope: String.t() | nil
        }
end
