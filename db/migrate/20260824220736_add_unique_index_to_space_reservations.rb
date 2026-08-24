class AddUniqueIndexToSpaceReservations < ActiveRecord::Migration[8.1]
  # Un (réservation d'espaces, espace, date) ne décrit qu'UNE occupation : la
  # salle est prise ce jour-là, et `duration` dit journée / soirée / les deux.
  # Des lignes jumelles doublaient les badges du calendrier, la ligne de
  # composition de la modale, et surtout l'occupation comptée par
  # `Space#available_on?` — une salle réservée une fois pouvait s'y compter deux
  # et bloquer une disponibilité réelle (46 lignes en prod, toutes nées le même
  # jour, cf. rake space_reservations:dedupe).
  #
  # La cause est corrigée en amont (`SpaceComposition#space_reservation_specs`
  # fusionne les entrées d'un même couple avant de persister) : cet index est le
  # filet, pas le mécanisme. Il ne doit jamais se déclencher.
  #
  # `date` est nullable et Postgres ne compare pas deux NULL : les rares lignes
  # sans date (3 en prod) restent hors contrainte. L'index est partiel sur les
  # lignes vivantes, par cohérence avec le reste du schéma — la colonne
  # `deleted_at` existe ici sans que le modèle soit soft-deletable.
  def change
    add_index :space_reservations,
              %i[space_booking_id space_id date],
              unique: true,
              where: "deleted_at IS NULL",
              name: "index_space_reservations_unique_live"
  end
end
