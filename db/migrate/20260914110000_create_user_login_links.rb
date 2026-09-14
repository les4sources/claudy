# Issue #306 — connexion par lien e-mail pour les comptes Devise.
#
# Le jeton n'est JAMAIS stocké en clair : seul son digest SHA256 l'est, comme
# pour `portal_otps`. On ne peut donc pas relire un lien depuis la base —
# seulement vérifier celui qu'on présente.
#
# La table est distincte de `portal_otps` à dessein : autre population
# (`User` et non `Customer`), autre mécanisme (lien et non code), autre
# session (Devise et non `sign_in_portal`). Les mêler obligerait à distinguer
# les lignes par une colonne de type, et la première requête écrite à la main
# se tromperait de population.
class CreateUserLoginLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :user_login_links do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      # Consommé = brûlé. Un lien ne sert qu'une fois, et une ligne consommée
      # reste en base : c'est elle qui empêche le rejeu, et elle compte encore
      # dans le rate-limit.
      t.datetime :consumed_at

      t.timestamps
    end

    # `(user_id, created_at)` sert les deux lectures chaudes : le rate-limit
    # horaire d'un utilisateur, et l'extinction de ses liens vivants.
    add_index :user_login_links, %i[user_id created_at]
    add_index :user_login_links, :token_digest
  end
end
