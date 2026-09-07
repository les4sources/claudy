class AddExternalRefToNotes < ActiveRecord::Migration[8.1]
  # `external_ref` porte l'idempotence des notes posées par l'API agent : une
  # réservation de pizza party (côté boulangerie) rejoue son POST tant qu'elle
  # n'a pas eu de réponse, et deux post-it identiques sur la même journée du
  # calendrier seraient pires que pas de post-it du tout.
  #
  # L'index est partiel sur les notes vivantes : une note supprimée en douceur
  # ne doit pas empêcher qu'on en repose une portant la même référence (le
  # `default_scope` du gem soft_deletion la rend déjà invisible partout).
  def change
    add_column :notes, :external_ref, :string

    add_index :notes,
              :external_ref,
              unique: true,
              where: "deleted_at IS NULL AND external_ref IS NOT NULL",
              name: "index_notes_on_external_ref_unique_live"
  end
end
