module Finance
  # Génère les écritures des charges récurrentes d'un mois (issue #159).
  #
  # Trois propriétés tiennent ce service :
  #
  # IDEMPOTENCE PAR LA BASE. Chaque écriture porte un `idempotency_key` de la
  # forme `recurring:<charge_id>:<YYYY-MM>`, garanti unique par l'index de la
  # phase 1. Générer deux fois le même mois ne crée jamais de doublon — et pas
  # parce qu'un `exists?` en Ruby a pensé à regarder, mais parce que la base
  # refuse. C'est ce qui rend la génération rejouable sans crainte.
  #
  # RÉSOLUTION DATÉE. Montant et effectif sont lus au 1er du mois traité, jamais
  # à aujourd'hui. Rejouer mars 2024 doit donner ce que mars 2024 devait.
  #
  # AUCUN ZÉRO SILENCIEUX. Une clé de barème qui ne résout rien ne crée pas une
  # écriture à 0 € : elle est signalée dans le rapport et rien n'est écrit.
  class GenerateRecurringCharges < ServiceBase
    Report = Struct.new(:created, :existing, :skipped, keyword_init: true) do
      def created_count = created.size
      def total_cents = created.sum { |line| line[:amount_cents] }
      def any? = created.any? || existing.any? || skipped.any?
    end

    def initialize(month:, dry_run: false, whodunnit: nil)
      @month = month.is_a?(String) ? Date.parse("#{month}-01") : month.to_date.beginning_of_month
      @dry_run = dry_run
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { month: @month }) { generate }
    end

    def run!
      generate
    end

    private

    def generate
      report = Report.new(created: [], existing: [], skipped: [])

      PaperTrail.request(whodunnit: @whodunnit || "recurring") do
        RecurringCharge.active_on(@month).includes(member_account: :household).each do |charge|
          process(charge, report)
        end
      end

      report
    end

    def process(charge, report)
      unit = charge.unit_amount_cents_on(@month)
      if unit.nil?
        return report.skipped << { charge: charge, reason: "barème « #{charge.rate_key} » non résolu au #{@month}" }
      end

      multiplier = charge.multiplier_on(@month)
      if multiplier.zero?
        return report.skipped << { charge: charge, reason: "aucun #{charge.basis == 'per_child' ? 'enfant' : 'adulte'} sur ce mois" }
      end

      lines_for(charge, unit, multiplier).each { |line| write(charge, line, report) }
    end

    # Une ou deux lignes selon que la part scindée résout encore quelque chose.
    # Le TOTAL dû est le même dans les deux cas — seule la ventilation change.
    def lines_for(charge, unit, multiplier)
      split_unit = charge.split_amount_cents_on(@month)
      total = unit * multiplier

      return [{ suffix: nil, label: charge.label, amount_cents: total }] if split_unit.nil?

      split_total = split_unit * multiplier
      [
        { suffix: nil, label: charge.label, amount_cents: total - split_total },
        { suffix: "split", label: charge.split_label.presence || "#{charge.label} — part scindée", amount_cents: split_total }
      ]
    end

    def write(charge, line, report)
      return if line[:amount_cents].zero?

      key = ["recurring", charge.id, @month.strftime("%Y-%m"), line[:suffix]].compact.join(":")

      if AccountEntry.unscoped.exists?(idempotency_key: key)
        return report.existing << { charge: charge, key: key }
      end

      entry_attributes = {
        member_account_id: charge.member_account_id,
        entry_date: @month.end_of_month,
        posted_at: Time.current,
        amount_cents: line[:amount_cents],
        flow: charge.flow,
        kind: charge.kind.presence || "recurring",
        label: line[:label],
        source: "recurring",
        idempotency_key: key
      }

      report.created << entry_attributes.merge(charge: charge)
      return if @dry_run

      AccountEntry.create!(entry_attributes)
    rescue ActiveRecord::RecordNotUnique
      # Deux générations concurrentes du même mois : l'index a tranché, et c'est
      # exactement le comportement voulu — on note l'existant, on ne lève pas.
      report.created.pop
      report.existing << { charge: charge, key: key }
    end
  end
end
