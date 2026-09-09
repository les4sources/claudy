module Activities
  # Le rappel « ces activités sont passées — ont-elles eu lieu ? »
  # (epic #244, phase 2).
  #
  # UN email par PORTEUR, pas un par créneau. Un porteur qui a animé douze
  # ateliers dans le trimestre recevrait douze mails, et n'en lirait aucun —
  # c'est la meilleure façon de faire ignorer le rappel de celui qui n'en a
  # qu'un.
  #
  # Dry-run par défaut : rien ne part sans `APPLY=1`. Un rappel envoyé par
  # erreur à quinze animateur·ice·s ne se rattrape pas.
  class OutcomeReminders
    Result = Struct.new(:carriers, :bookings_count, :skipped, keyword_init: true) do
      def to_s
        "#{carriers.size} porteur(s), #{bookings_count} créneau(x)" \
          "#{", #{skipped.size} sans email" if skipped.any?}"
      end
    end

    def initialize(dry_run: true)
      @dry_run = dry_run
    end

    def run
      result = Result.new(carriers: [], bookings_count: 0, skipped: [])

      by_carrier.each do |human, bookings|
        if human.email.blank?
          result.skipped << "#{human.name} (#{bookings.size} créneau(x))"
          next
        end

        result.carriers << "#{human.name} — #{bookings.size} créneau(x)"
        result.bookings_count += bookings.size
        ActivityOutcomeMailer.reminder(human, bookings).deliver_now unless @dry_run
      end

      result
    end

    private

    # Groupé par porteur via l'activité. Une activité sans porteur rattaché n'a
    # personne à relancer : elle reste dans l'écran « À confirmer » de l'admin,
    # qui est le bon endroit pour la voir.
    def by_carrier
      ExperienceBooking.awaiting_outcome
                       .includes(experience_availability: { experience: :human }, stay: :customer)
                       .order("experience_availabilities.available_on ASC")
                       .group_by { |booking| booking.experience&.human }
                       .except(nil)
    end
  end
end
