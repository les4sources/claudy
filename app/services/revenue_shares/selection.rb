module RevenueShares
  # Ce que le relevé d'une période RETIENT, et ce qu'il écarte — avec la raison.
  #
  # Objet de lecture pure : il ne crée rien. `Generate` s'en sert pour poser les
  # lignes, et l'écran de brouillon pour montrer, à côté, les réservations
  # laissées de côté. Les deux disent alors la même chose, parce que c'est
  # littéralement le même calcul.
  #
  # RÈGLE CENTRALE (décision 3) : la base est LUE, jamais recalculée. On somme
  # `bookings.price_cents` — le montant persisté à l'encodage de la réservation
  # Airbnb — et on ne rejoue aucune grille tarifaire par-dessus.
  class Selection
    Retained = Struct.new(:booking, :amount_cents, :kind, :origin_line, :label, keyword_init: true) do
      def adjustment? = kind == "adjustment"
    end
    Excluded = Struct.new(:booking, :reason, keyword_init: true)

    def initialize(agreement:, period_from:, period_to:, except_statement: nil)
      @agreement = agreement
      @from = period_from
      @to = period_to
      @except_statement = except_statement
    end

    def retained = @retained ||= (booking_lines + adjustment_lines)

    def excluded = @excluded ||= build_excluded

    def base_cents = retained.sum(&:amount_cents)

    def share_cents = @agreement.share_of(base_cents)

    private

    # Les réservations de l'hébergement dont le séjour CHEVAUCHE la période. On
    # ratisse plus large que la règle d'éligibilité (arrivée dans la période)
    # exprès : une réservation à cheval sur deux trimestres doit apparaître dans
    # les écartées avec sa raison, plutôt que de disparaître sans un mot.
    def candidates
      @candidates ||= Booking.where(lodging_id: @agreement.lodging_id)
                             .where("bookings.from_date <= ? AND bookings.to_date >= ?", @to, @from)
                             .includes(:stay)
                             .order(:from_date, :id)
                             .to_a
    end

    def booking_lines
      candidates.filter_map do |booking|
        next if cancelled?(booking)
        next unless arrives_in_period?(booking)
        next if reported_cents(booking).present?

        Retained.new(booking: booking, amount_cents: booking.price_cents.to_i, kind: "booking",
                     label: booking_label(booking))
      end
    end

    # Les régularisations (décision 5). On balaie TOUTES les réservations déjà
    # relevées par cet accord — pas seulement celles de la période — parce que
    # c'est justement une réservation d'un trimestre passé dont le prix a bougé
    # qu'on cherche à rattraper.
    def adjustment_lines
      previous_lines.group_by(&:booking_id).filter_map do |booking_id, lines|
        booking = lines.first.booking
        next if booking.blank?

        drift = booking.price_cents.to_i - lines.sum(&:amount_cents)
        next if drift.zero?

        origin = lines.find { |line| line.kind == "booking" } || lines.first
        Retained.new(booking: booking, amount_cents: drift, kind: "adjustment", origin_line: origin,
                     label: "Régularisation — #{booking_label(booking)}")
      end
    end

    def build_excluded
      candidates.filter_map do |booking|
        if cancelled?(booking)
          Excluded.new(booking: booking, reason: "annulée")
        elsif !arrives_in_period?(booking)
          Excluded.new(booking: booking, reason: "arrivée hors période")
        elsif reported_cents(booking).present? &&
              booking.price_cents.to_i == reported_cents(booking)
          Excluded.new(booking: booking, reason: "déjà relevée")
        end
      end
    end

    # Une réservation annulée ne rapporte rien : ni aux 4 Sources, ni aux
    # propriétaires. On lit l'annulation des deux côtés — la réservation
    # elle-même et le séjour qui la porte — parce que le geste d'annulation
    # passe tantôt par l'une, tantôt par l'autre.
    def cancelled?(booking)
      booking.status.in?(%w[canceled cancelled declined]) || booking.stay&.canceled?
    end

    def arrives_in_period?(booking)
      booking.from_date.present? && booking.from_date >= @from && booking.from_date <= @to
    end

    # Ce que cet accord a déjà relevé pour cette réservation, toutes lignes
    # confondues (relevé initial + régularisations). `nil` si jamais relevée.
    def reported_cents(booking)
      totals = previous_totals
      totals.key?(booking.id) ? totals[booking.id] : nil
    end

    def previous_totals
      @previous_totals ||= previous_lines.group_by(&:booking_id)
                                         .transform_values { |lines| lines.sum(&:amount_cents) }
    end

    def previous_lines
      @previous_lines ||= begin
        scope = RevenueShareStatementLine
                .joins(:revenue_share_statement)
                .where(revenue_share_statements: { revenue_share_agreement_id: @agreement.id })
                .includes(:booking)
        scope = scope.where.not(revenue_share_statement_id: @except_statement.id) if @except_statement&.persisted?
        scope.to_a
      end
    end

    def booking_label(booking)
      nom = [booking.group_name, [booking.firstname, booking.lastname].compact_blank.join(" ")]
            .compact_blank.first
      nom.presence || "Réservation ##{booking.id}"
    end
  end
end
