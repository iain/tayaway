# frozen_string_literal: true

Sequel.migration do
  up do
    rename_table :magic_link_tokens, :login_link_tokens
  end

  down do
    rename_table :login_link_tokens, :magic_link_tokens
  end
end
