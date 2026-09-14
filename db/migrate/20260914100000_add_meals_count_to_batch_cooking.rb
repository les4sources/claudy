# Issue #307 — la saisie du batch cooking parle en PERSONNES et en REPAS.
#
# Stéphanie ne compte pas des portions en cuisine : elle sait combien de
# personnes compte chaque ménage, et combien de repas la session a préparés.
# Le formulaire lui demandait des portions ; elle y a tapé des personnes, et la
# première session réelle est partie facturée cinq fois trop bas.
#
# On renomme donc la colonne pour ce qu'elle contient DÉJÀ — des personnes — et
# on met le nombre de repas sur la session. Aucune valeur n'est convertie :
# c'est un renommage, pas une migration de données.
#
# `total_portions` reste un cache d'affichage et se recalcule ici. La migration
# n'écrit AUCUNE écriture comptable : rejouer les écritures est le travail de
# `rake batch_cooking:replay_entries`, lancé à la main après déploiement, parce
# qu'une écriture verrouillée doit pouvoir faire échouer le rejeu sans faire
# échouer la migration.
class AddMealsCountToBatchCooking < ActiveRecord::Migration[8.1]
  def up
    # 5 repas : c'est ce que prépare une session ordinaire, et c'est le compte
    # de la seule session déjà encodée en production — rien à backfiller.
    add_column :batch_cooking_sessions, :meals_count, :integer, null: false, default: 5

    remove_check_constraint :batch_cooking_servings, "portions > 0",
                            name: "bc_servings_portions_positive"
    rename_column :batch_cooking_servings, :portions, :people
    add_check_constraint :batch_cooking_servings, "people > 0",
                         name: "bc_servings_people_positive"

    recalculer_le_cache
  end

  def down
    remove_check_constraint :batch_cooking_servings, "people > 0",
                            name: "bc_servings_people_positive"
    rename_column :batch_cooking_servings, :people, :portions
    add_check_constraint :batch_cooking_servings, "portions > 0",
                         name: "bc_servings_portions_positive"

    remove_column :batch_cooking_sessions, :meals_count

    execute(<<~SQL.squish)
      UPDATE batch_cooking_sessions
      SET total_portions = COALESCE((
        SELECT SUM(portions) FROM batch_cooking_servings
        WHERE batch_cooking_servings.batch_cooking_session_id = batch_cooking_sessions.id
      ), 0)
    SQL
  end

  private

  def recalculer_le_cache
    execute(<<~SQL.squish)
      UPDATE batch_cooking_sessions
      SET total_portions = meals_count * COALESCE((
        SELECT SUM(people) FROM batch_cooking_servings
        WHERE batch_cooking_servings.batch_cooking_session_id = batch_cooking_sessions.id
      ), 0)
    SQL
  end
end
