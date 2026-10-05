# Serveur MCP de Claudy (Michael, 2026-10-05) : Claude se connecte à Claudy
# comme un connecteur claude.ai, par OAuth. Ces trois tables sont le serveur
# d'autorisation minimal qui va avec — les clients enregistrés (claude.ai,
# Claude Code), les codes d'autorisation, les jetons.
#
# Aucun secret n'est stocké en clair : codes et jetons sont gardés sous forme
# d'empreinte SHA-256. Une base copiée ne donne accès à rien.
class CreateMcpOauth < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_clients do |t|
      t.string :client_id, null: false
      t.string :name
      t.string :redirect_uris, array: true, null: false, default: []
      t.timestamps
    end
    add_index :mcp_clients, :client_id, unique: true

    create_table :mcp_grants do |t|
      t.references :mcp_client, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :code_digest, null: false
      t.string :code_challenge, null: false
      t.string :redirect_uri, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end
    add_index :mcp_grants, :code_digest, unique: true

    create_table :mcp_tokens do |t|
      t.references :mcp_client, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :access_digest, null: false
      t.string :refresh_digest, null: false
      t.datetime :access_expires_at, null: false
      t.datetime :refresh_expires_at, null: false
      t.datetime :revoked_at
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :mcp_tokens, :access_digest, unique: true
    add_index :mcp_tokens, :refresh_digest, unique: true
  end
end
