# Epic Cuisine (#219), phase 1 — bascule des deux types historiques vers la
# nomenclature des cinq familles. `unscoped` : les lignes soft-deleted portent
# aussi l'ancien type et doivent suivre, sinon un séjour restauré se retrouve
# avec un `kind` que le modèle refuse.
class MigrateMealKindsToKitchenFamilies < ActiveRecord::Migration[8.1]
  KIND_MAP = { "repas_vege_midi" => "repas", "buffet" => "buffet_vege" }.freeze

  RATE_MAP = {
    "meal.repas_vege_midi.per_person" => "meal.repas.per_person",
    "meal.buffet.per_person"          => "meal.buffet_vege.per_person"
  }.freeze

  def up
    rename_kinds(KIND_MAP)
    rename_rate_keys(RATE_MAP)
  end

  def down
    rename_kinds(KIND_MAP.invert)
    rename_rate_keys(RATE_MAP.invert)
  end

  private

  def rename_kinds(map)
    map.each do |from, to|
      execute("UPDATE meal_orders SET kind = #{quote(to)} WHERE kind = #{quote(from)}")
    end
  end

  # Une clé de tarif est unique : on ne renomme que si la cible est libre,
  # sinon on laisse la ligne en place plutôt que de casser la migration.
  def rename_rate_keys(map)
    map.each do |from, to|
      execute(<<~SQL.squish)
        UPDATE rates SET key = #{quote(to)}
        WHERE key = #{quote(from)}
          AND NOT EXISTS (SELECT 1 FROM rates WHERE key = #{quote(to)})
      SQL
    end
  end
end
