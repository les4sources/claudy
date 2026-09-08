# Issue #238 — le goûter devient un service facturable à part, et le type `trio`
# disparaît des types proposables : c'est désormais un bouton de la grille, pas
# une prestation.
#
# Aucune ligne existante ne doit être cassée. S'il reste une ligne `trio` en
# base, la migration ÉCHOUE bruyamment plutôt que de laisser une ligne orpheline
# d'un type qu'on ne propose plus : elle serait invisible à l'édition et
# incalculable au total.
class AddGouterMealKind < ActiveRecord::Migration[8.1]
  def up
    trios = MealOrder.with_deleted { MealOrder.where(kind: "trio").count }
    return if trios.zero?

    raise <<~MESSAGE
      #{trios} ligne(s) de cuisine sont encore de type `trio`.

      Le type `trio` n'est plus une prestation : c'est le bouton « Trio » de la
      grille de saisie, qui coche midi + goûter + soir. Convertis ces lignes en
      trois lignes (`repas` midi, `gouter`, `repas` soir) avant de migrer —
      elles seront alors ramenées au prix de formule par la remise.

      Pour les retrouver :
        MealOrder.with_deleted { MealOrder.where(kind: "trio").pluck(:id, :stay_id, :date) }
    MESSAGE
  end

  def down; end
end
