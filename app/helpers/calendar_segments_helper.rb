# Découpage d'un séjour en segments de barre, une ligne de semaine à la fois
# (issue #10, Phase 1). Le calendrier mensuel est une grille de 7 colonnes par
# semaine ; on dessine par-dessus une bande de **14 demi-colonnes** pour que la
# barre démarre au milieu du jour d'arrivée (après-midi) et finisse au milieu du
# jour de départ (matin), comme dans n'importe quel calendrier de booking.
#
# Colonnes (1-indexées, comme CSS grid) pour le jour d'indice d dans la semaine :
#   AM = 2d + 1   ·   PM = 2d + 2
#
# Une extrémité qui tombe hors de la semaine affichée est « coupée » : le segment
# occupe alors la cellule entière de ce côté (bord droit, pas d'arrondi).
module CalendarSegmentsHelper
  HALF_COLUMNS_PER_WEEK = 14

  Segment = Struct.new(:start_column, :span, :starts_stay, :ends_stay, keyword_init: true) do
    def starts_stay? = starts_stay
    def ends_stay? = ends_stay

    # Arrondi seulement du côté où le séjour commence/finit réellement.
    def rounded_classes
      classes = []
      classes << "rounded-l-full" if starts_stay
      classes << "rounded-r-full" if ends_stay
      classes.join(" ")
    end
  end

  # Segment d'un séjour [from_date, to_date] sur une semaine donnée (tableau de
  # 7 dates consécutives). nil si le séjour ne touche pas cette semaine.
  def calendar_segment_for(week_days, from_date, to_date)
    return nil if week_days.blank? || from_date.blank? || to_date.blank?
    return nil if to_date <= from_date # un séjour de 0 nuit n'a pas de barre

    week_start = week_days.first
    week_end   = week_days.last
    return nil if from_date > week_end || to_date < week_start

    segment_start = [from_date, week_start].max
    segment_end   = [to_date, week_end].min

    starts_stay = segment_start == from_date
    ends_stay   = segment_end == to_date

    first_index = (segment_start - week_start).to_i
    last_index  = (segment_end - week_start).to_i

    start_column = (2 * first_index) + (starts_stay ? 2 : 1)
    end_column   = (2 * last_index) + (ends_stay ? 1 : 2)
    return nil if end_column < start_column

    Segment.new(
      start_column: start_column,
      span: end_column - start_column + 1,
      starts_stay: starts_stay,
      ends_stay: ends_stay
    )
  end

  # Les segments d'une semaine, un par booking, dans un ordre stable (hébergement
  # puis date de création) : deux rendus successifs empilent les barres pareil.
  def calendar_booking_segments(week_days, bookings)
    Array(bookings).filter_map do |booking|
      segment = calendar_segment_for(week_days, booking.from_date, booking.to_date)
      next if segment.nil?

      [booking, segment]
    end
  end

  # Style inline plutôt que classes Tailwind : les classes dynamiques
  # (`col-start-#{n}`) ne sont pas compilées par le JIT, et la grille de 14
  # demi-colonnes n'existe pas dans la config par défaut.
  def calendar_segment_style(segment, row)
    "grid-column: #{segment.start_column} / span #{segment.span}; grid-row: #{row};"
  end
end
