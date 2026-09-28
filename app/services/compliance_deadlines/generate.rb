module ComplianceDeadlines
  # Fait correspondre les échéances aux règles (échéancier comptable).
  #
  # Idempotent : relancé cent fois, il ne crée que ce qui manque. Une échéance
  # existante n'est JAMAIS réécrite — sa date a pu être avancée à la main, et la
  # règle n'a pas à l'écraser.
  #
  # Quand une règle change (première échéance déplacée, fréquence revue), les
  # échéances FUTURES qu'elle ne produit plus sont retirées — mais seulement si
  # personne n'y a touché : ni note, ni preuve, ni facture, ni état. Une échéance
  # sur laquelle quelqu'un a travaillé reste, quitte à être close à la main.
  class Generate < ServiceBase
    HORIZON_MONTHS = 12

    Report = Struct.new(:created, :removed, keyword_init: true) do
      def to_s = "#{created} échéance(s) créée(s), #{removed} retirée(s)"
    end

    def initialize(obligations: ComplianceObligation.all, horizon: Date.current >> HORIZON_MONTHS, today: Date.current)
      @obligations = obligations
      @horizon = horizon
      @today = today
    end

    def run = catch_error(context: { horizon: @horizon }) { run! }

    def run!
      report = Report.new(created: 0, removed: 0)
      @obligations.includes(:compliance_deadlines).find_each do |obligation|
        sync(obligation, report)
      end
      report
    end

    private

    def sync(obligation, report)
      schedule = obligation.active? ? obligation.schedule_through(@horizon) : []
      existing = obligation.compliance_deadlines.index_by(&:period_start)

      schedule.each do |period_start, due_on|
        next if existing.key?(period_start)

        obligation.compliance_deadlines.create!(period_start: period_start, due_on: due_on)
        report.created += 1
      end

      expected = schedule.map(&:first)
      existing.each_value do |deadline|
        next if expected.include?(deadline.period_start)
        next unless untouched_future?(deadline)

        deadline.soft_delete!(validate: false)
        report.removed += 1
      end
    end

    def untouched_future?(deadline)
      deadline.due_on >= @today &&
        deadline.status == "todo" &&
        deadline.note.blank? &&
        deadline.purchase_invoice_id.blank? &&
        !deadline.proof.attached?
    end
  end
end
