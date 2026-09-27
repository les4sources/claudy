# Carte du domaine (issue #370) : un tracé peut représenter PLUSIEURS gîtes ou
# salles — la Chevêche au rez-de-chaussée et la Hulotte à l'étage du même
# bâtiment. Le lien unique `map_features.linked_type/linked_id` cède la place à
# une table de liaison ; chaque gîte ou salle n'a toujours qu'UN tracé (index
# unique). Les liaisons d'un tracé supprimé (soft-delete) sont effacées par le
# modèle : la table ne contient que des tracés vivants.
#
# Non destructif : les colonnes `linked_type`/`linked_id` restent en place (le
# code ne les lit plus, cf. `MapFeature.ignored_columns`) ; leur suppression
# fera l'objet d'une migration séparée.
class CreateMapFeatureVenues < ActiveRecord::Migration[8.1]
  def up
    create_table :map_feature_venues do |t|
      t.references :map_feature, null: false, foreign_key: true
      t.string :venue_type, null: false
      t.bigint :venue_id, null: false
      t.timestamps
    end
    add_index :map_feature_venues, %i[venue_type venue_id], unique: true

    backfill_from_linked
    remove_index :map_features, name: "index_map_features_on_linked_unique_live"
  end

  def down
    restore_linked
    add_index :map_features, %i[linked_type linked_id], unique: true,
              where: "deleted_at IS NULL AND linked_id IS NOT NULL",
              name: "index_map_features_on_linked_unique_live"
    drop_table :map_feature_venues
  end

  # Chaque tracé VIVANT relié à un gîte ou une salle obtient sa liaison.
  # Rejouable sans doublon.
  def backfill_from_linked
    execute <<~SQL.squish
      INSERT INTO map_feature_venues (map_feature_id, venue_type, venue_id, created_at, updated_at)
      SELECT id, linked_type, linked_id, NOW(), NOW()
      FROM map_features
      WHERE deleted_at IS NULL AND linked_type IN ('Lodging', 'Space') AND linked_id IS NOT NULL
      ON CONFLICT (venue_type, venue_id) DO NOTHING
    SQL
  end

  # Retour arrière : chaque tracé reprend dans `linked_*` son premier lieu —
  # un tracé à plusieurs lieux n'en garde qu'un, faute de mieux.
  def restore_linked
    execute "UPDATE map_features SET linked_type = NULL, linked_id = NULL"
    execute <<~SQL.squish
      UPDATE map_features SET linked_type = first_venue.venue_type, linked_id = first_venue.venue_id
      FROM (
        SELECT DISTINCT ON (map_feature_id) map_feature_id, venue_type, venue_id
        FROM map_feature_venues ORDER BY map_feature_id, id
      ) AS first_venue
      WHERE map_features.id = first_venue.map_feature_id
    SQL
  end
end
