# Epic #246, phase 1 — le batch cooking : un repas préparé pour les sourciers.
#
# Trois tables, parce qu'une session porte DEUX listes qui ne parlent pas de la
# même chose : ce que chaque ménage a reçu (ce qu'il doit) et ce que chaque
# cuisinier a préparé (ce qu'on lui doit). Les mêler dans une seule table
# obligerait à distinguer les lignes par une colonne de type, et le premier
# rapport écrit à la main se tromperait de sens.
#
# Les écritures comptables, elles, ne vivent PAS ici : elles se génèrent depuis
# ces lignes par `Finance::RecordBatchCooking`, jamais l'inverse.
class CreateBatchCookingSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :batch_cooking_sessions do |t|
      t.date   :cooked_on, null: false
      t.string :label
      t.text   :notes
      # Qui a saisi. Un utilisateur Claudy, pas un `Human` : les cuisiniers ont
      # un accès, et c'est ce compte-là qui répond de la saisie.
      t.references :created_by, foreign_key: { to_table: :users }
      # Total des portions CUISINÉES, tenu à jour depuis les lignes de service.
      # Redondant par construction — et c'est assumé : la liste des sessions
      # affiche ce total, et le recalculer par session ferait une requête par
      # ligne d'écran.
      t.integer :total_portions, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :batch_cooking_sessions, :deleted_at
    add_index :batch_cooking_sessions, :cooked_on

    # Ce qu'un ménage a reçu. Le compte, pas le ménage : c'est le compte qui
    # porte la charge, et un ménage peut en avoir plusieurs.
    create_table :batch_cooking_servings do |t|
      t.references :batch_cooking_session, null: false, foreign_key: true,
                                           index: { name: "index_bc_servings_on_session" }
      t.references :member_account, null: false, foreign_key: true
      t.integer :portions, null: false

      t.timestamps
    end

    # Un ménage servi UNE fois par session. Sans cet index, une double
    # soumission crée deux lignes, et la clé d'idempotence des écritures — qui
    # ne connaît que la session et le compte — n'en couvrirait qu'une.
    add_index :batch_cooking_servings, %i[batch_cooking_session_id member_account_id],
              unique: true, name: "index_bc_servings_unique"
    add_check_constraint :batch_cooking_servings, "portions > 0",
                         name: "bc_servings_portions_positive"

    # Qui a cuisiné, et pour combien de portions. `portions` peut valoir zéro :
    # quelqu'un qui a donné un coup de main sans qu'on lui attribue de part
    # reste dans la liste, il ne gagne simplement rien.
    create_table :batch_cooking_cooks do |t|
      t.references :batch_cooking_session, null: false, foreign_key: true,
                                           index: { name: "index_bc_cooks_on_session" }
      t.references :human, null: false, foreign_key: true
      t.integer :portions, null: false, default: 0

      t.timestamps
    end

    add_index :batch_cooking_cooks, %i[batch_cooking_session_id human_id],
              unique: true, name: "index_bc_cooks_unique"
    add_check_constraint :batch_cooking_cooks, "portions >= 0",
                         name: "bc_cooks_portions_not_negative"
  end
end
