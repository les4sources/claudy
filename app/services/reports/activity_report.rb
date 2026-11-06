module Reports
  # Le reporting des activités (ânes, grimpe dans les arbres, ateliers…), à côté
  # de celui des hébergements et de la cuisine, sous Accueil › Reporting.
  #
  # CE QUI COMPTE. Une réservation d'activité CONFIRMÉE (le porteur a validé),
  # dont le séjour n'est pas annulé, et dont le créneau tombe dans l'année. La
  # date de référence est celle du CRÉNEAU, jamais celle de la réservation : une
  # balade réservée en mars pour juillet se lit en juillet, comme une nuitée se
  # lit à la date d'arrivée dans le tableau des hébergements.
  #
  # Les réservations « à valider » restent à part (`pending_totals`) : elles ne
  # sont pas exigibles (`Stay#experiences_pending_amount_cents`), elles n'entrent
  # donc pas dans le chiffre d'affaires. Les refusées et annulées n'existent pas.
  #
  # LE MONTANT est celui que le séjour facture : `Pricing::ExperienceLine`, la
  # source unique du barème (forfait + €/pers × participants). Une activité
  # confirmée qui « n'a pas eu lieu » reste comptée : le séjour la facture tant
  # qu'on ne l'annule pas. La tenue est donnée à côté, pour qu'on le voie.
  #
  # LA RÉMUNÉRATION des porteurs est celle figée sur la réservation à sa
  # confirmation (`carrier_fee_cents`). Une réservation sans montant (activité
  # sans durée) est comptée dans `missing_fee`, jamais comme zéro euro.
  class ActivityReport
    Totals = Struct.new(:bookings, :participants, :revenue_cents, :carrier_fee_cents,
                        :missing_fee, keyword_init: true) do
      def self.empty = new(bookings: 0, participants: 0, revenue_cents: 0, carrier_fee_cents: 0, missing_fee: 0)

      def margin_cents = revenue_cents - carrier_fee_cents

      def average_participants
        return 0 if bookings.zero?

        (participants.to_f / bookings).round(1)
      end

      def any? = bookings.positive?
    end

    # Une ligne du tableau « par activité ». `experience` peut être une activité
    # supprimée depuis : son historique reste dans l'année où il a eu lieu.
    Row = Struct.new(:experience, :totals, :held, :no_show, :to_declare, :upcoming, keyword_init: true) do
      def name = experience&.name || "Activité supprimée"

      def color = experience&.color.presence || "#94a3b8"

      def deleted? = experience.nil? || experience.deleted_at.present?
    end

    def initialize(year:, today: Date.current)
      @year  = year.to_i
      @today = today
    end

    attr_reader :year

    def totals = @totals ||= totals_for(confirmed_bookings)

    def pending_totals = @pending_totals ||= totals_for(pending_bookings)

    # Douze mois, dans l'ordre, même vides : le tableau se lit comme celui des
    # finances, un mois sans activité se voit.
    def by_month
      @by_month ||= begin
        grouped = confirmed_bookings.group_by { |booking| booking.experience_availability.available_on.month }
        (1..12).index_with { |month| totals_for(grouped.fetch(month, [])) }
      end
    end

    # Les activités de l'année, de celle qui rapporte le plus à celle qui
    # rapporte le moins (à égalité : le nom).
    def by_experience
      @by_experience ||=
        confirmed_bookings.group_by { |booking| booking.experience_availability.experience_id }
                          .map { |experience_id, group| row_for(experiences_by_id[experience_id], group) }
                          .sort_by { |row| [-row.totals.revenue_cents, row.name] }
    end

    # Part d'une activité dans le chiffre d'affaires de l'année, de 0 à 100.
    def share_of(row)
      return 0 if totals.revenue_cents.zero?

      (row.totals.revenue_cents * 100.0 / totals.revenue_cents).round(1)
    end

    # La tenue des réservations confirmées de l'année.
    def outcomes
      @outcomes ||= {
        held: confirmed_bookings.count(&:held?),
        no_show: confirmed_bookings.count(&:no_show?),
        to_declare: confirmed_bookings.count { |booking| to_declare?(booking) },
        upcoming: confirmed_bookings.count { |booking| upcoming?(booking) }
      }
    end

    def any? = confirmed_bookings.any? || pending_bookings.any?

    # Le prix d'une réservation, au barème de son activité — celle-ci fût-elle
    # supprimée depuis (`Experience` a un `default_scope` de soft deletion, que
    # l'association ne traverse pas).
    def price_cents(booking)
      experience = experiences_by_id[booking.experience_availability.experience_id]
      return 0 if experience.nil?

      Pricing::ExperienceLine.amount_cents(experience, participants: booking.participants)
    end

    private

    attr_reader :today

    def year_range = Date.new(year, 1, 1)..Date.new(year, 12, 31)

    def confirmed_bookings = @confirmed_bookings ||= scope.confirmed.to_a

    def pending_bookings = @pending_bookings ||= scope.pending.to_a

    # `joins(:stay)` traverse le `default_scope` de `Stay` : un séjour supprimé
    # n'emporte pas ses activités dans le reporting. Un statut de séjour vide
    # n'est pas un séjour annulé — d'où le `IS NULL`.
    def scope
      ExperienceBooking.joins(:stay, :experience_availability)
                       .where(experience_availabilities: { available_on: year_range })
                       .where("stays.status IS NULL OR stays.status NOT IN (?)", Stay::CANCELED_STATUSES)
                       .includes(:experience_availability)
                       .order("experience_availabilities.available_on", :id)
    end

    def experiences_by_id
      @experiences_by_id ||= begin
        ids = (confirmed_bookings + pending_bookings).map { |booking| booking.experience_availability.experience_id }.uniq
        Experience.unscoped.includes(:human).where(id: ids).index_by(&:id)
      end
    end

    def totals_for(group)
      Totals.new(
        bookings: group.size,
        participants: group.sum { |booking| booking.participants.to_i },
        revenue_cents: group.sum { |booking| price_cents(booking) },
        carrier_fee_cents: group.sum { |booking| booking.carrier_fee_cents.to_i },
        missing_fee: group.count { |booking| booking.carrier_fee_cents.nil? }
      )
    end

    def row_for(experience, group)
      Row.new(
        experience: experience,
        totals: totals_for(group),
        held: group.count(&:held?),
        no_show: group.count(&:no_show?),
        to_declare: group.count { |booking| to_declare?(booking) },
        upcoming: group.count { |booking| upcoming?(booking) }
      )
    end

    def to_declare?(booking)
      !booking.outcome_recorded? && booking.experience_availability.available_on < today
    end

    def upcoming?(booking)
      !booking.outcome_recorded? && booking.experience_availability.available_on >= today
    end
  end
end
