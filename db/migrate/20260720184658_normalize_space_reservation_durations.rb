class NormalizeSpaceReservationDurations < ActiveRecord::Migration[7.0]
  # La composition de séjour (funnel + admin) persistait les périodes de PRICING
  # ("journee"/"soiree"/"journee_et_soiree") dans `space_reservations.duration`,
  # alors que tout l'affichage lit le vocabulaire canonique tranche 1
  # ("day"/"evening"/"fullday") → « période non précisée » partout. Le code
  # persiste désormais le canonique ; on normalise l'existant. Idempotent,
  # inclut les lignes soft-deleted (données d'affichage historiques).
  MAPPING = {
    "journee"           => "day",
    "soiree"            => "evening",
    "journee_et_soiree" => "fullday"
  }.freeze

  def up
    MAPPING.each do |period, duration|
      execute <<~SQL
        UPDATE space_reservations SET duration = #{quote(duration)} WHERE duration = #{quote(period)}
      SQL
    end

    # Même bug, volet dates : la composition posait from/to_date sur la fenêtre
    # du séjour au lieu des dates réellement réservées (« du 21 au 23 » pour une
    # salle du seul 22). On réaligne sur min/max des SpaceReservation VIVANTES,
    # uniquement là où ça diverge — les données historiques cohérentes (canal
    # direct tranche 1, from/to == bornes des réservations) ne bougent pas.
    execute <<~SQL
      UPDATE space_bookings sb
      SET from_date = bounds.min_date, to_date = bounds.max_date
      FROM (
        SELECT space_booking_id, MIN(date) AS min_date, MAX(date) AS max_date
        FROM space_reservations
        WHERE deleted_at IS NULL
        GROUP BY space_booking_id
      ) bounds
      WHERE bounds.space_booking_id = sb.id
        AND (sb.from_date IS DISTINCT FROM bounds.min_date
          OR sb.to_date   IS DISTINCT FROM bounds.max_date)
    SQL
  end

  def down
    # Volontairement irréversible : on ne sait pas distinguer un "day" historique
    # d'un "day" normalisé. Le vocabulaire canonique reste valide dans les deux mondes.
  end

  private

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
