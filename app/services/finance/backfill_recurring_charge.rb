module Finance
  # Rattrape l'historique d'une charge récurrente posée APRÈS COUP sur un compte
  # (la pension de Balthazar chez Béné : payée tous les mois depuis 2022, mais
  # la règle n'existe dans claudy que depuis octobre 2026).
  #
  # Deux moitiés, qui doivent tomber ensemble :
  #
  #   1. LA DETTE — une écriture par mois depuis le début de la règle, posée par
  #      le générateur lui-même (`only:`), donc avec sa clé `recurring:<id>:<mois>`
  #      et son montant daté. Le générateur ne la refera jamais.
  #   2. LES PAIEMENTS — un règlement par virement retrouvé à la banque. Deux cas :
  #      - la ligne est DÉJÀ AFFECTÉE (2022-2025 : passée en produit lors de la
  #        reprise Winbooks) : on n'y touche pas, la comptabilité générale est
  #        juste. Seul le compte courant reçoit son règlement, un par mois payé,
  #        avec la référence « reprise-<poste>:AAAA-MM » qui lui fait payer CE
  #        mois-là ;
  #      - la ligne est ENCORE À AFFECTER : le geste habituel,
  #        `RecordMemberSettlement` — règlement + affectation en 400000.
  #
  # Un virement paie le mois où il arrive ; un multiple du montant paie autant de
  # mois, en remontant (« Balthazar - fev-mars », 60 € le 16 mars). Ce qui n'est
  # pas un multiple du montant mensuel n'est pas deviné : il est laissé de côté
  # et le rapport le dit.
  #
  # Tout ou rien, et rejouable : chaque écriture porte une clé d'idempotence.
  class BackfillRecurringCharge < ServiceBase
    Report = Struct.new(:charges, :settlements, :links, :skipped, :paid_unbilled, :billed_unpaid, keyword_init: true) do
      def billed_cents = charges.sum { |c| c[:amount_cents] }
      def paid_cents = settlements.sum { |s| s[:amount_cents] } + links.sum { |l| l[:amount_cents] }
    end

    class ScopedCharge < StandardError; end

    def initialize(charge:, cash_entries:, through: Date.current, apply: false, whodunnit: nil)
      @charge = charge
      @account = charge.member_account
      @cash_entries = cash_entries
      @through = through.to_date.beginning_of_month
      @apply = apply
      @whodunnit = whodunnit || "rattrapage-charge-#{charge.id}"
    end

    def run = catch_error(context: { charge: @charge&.id }) { backfill }
    def run! = backfill

    private

    def backfill
      raise ScopedCharge, "Seule une charge visant UN compte se rattrape ainsi." if @charge.scoped?

      report = Report.new(charges: [], settlements: [], links: [], skipped: [], paid_unbilled: [], billed_unpaid: [])

      PaperTrail.request(whodunnit: @whodunnit) do
        ApplicationRecord.transaction do
          bill(report)
          pay(report)
        end
      end

      compare(report)
      report
    end

    def months
      first = @charge.starts_on.beginning_of_month
      last = [@charge.ends_on&.beginning_of_month, @through].compact.min
      (0..).lazy.map { |i| first >> i }.take_while { |m| m <= last }.to_a
    end

    def bill(report)
      months.each do |month|
        generated = Finance::GenerateRecurringCharges.new(month: month, dry_run: !@apply, only: @charge.id,
                                                          whodunnit: @whodunnit).run!
        generated.created.each { |line| report.charges << { month: month, amount_cents: line[:amount_cents], status: :new } }
        generated.existing.each do |line|
          entry = AccountEntry.unscoped.find_by(idempotency_key: line[:key])
          report.charges << { month: month, amount_cents: entry&.amount_cents.to_i, status: :existing }
        end
        generated.skipped.each { |line| report.skipped << { month: month, reason: line[:reason] } }
      end
    end

    def pay(report)
      @cash_entries.incoming.where.not(status: "excluded").order(:entry_date, :id).each do |entry|
        month = entry.entry_date.beginning_of_month
        unit = @charge.unit_amount_cents_on(month)

        if unit.nil?
          report.skipped << { entry: entry, reason: "barème « #{@charge.rate_key} » non résolu en #{month.strftime('%Y-%m')}" }
          next
        end
        if (entry.amount_cents % unit).nonzero?
          report.skipped << { entry: entry, reason: "#{money(entry.amount_cents)} n'est pas un multiple du montant mensuel" }
          next
        end

        paid_months = (entry.amount_cents / unit).times.map { |i| month << i }.reverse

        if entry.cash_allocations.where(document: @account).exists?
          report.links << { entry: entry, months: paid_months, amount_cents: entry.amount_cents, status: :existing }
        elsif entry.cash_allocations.none?
          link(entry, paid_months, report)
        elsif entry.fully_allocated?
          paid_months.each { |m| settle(entry, m, unit, report) }
        else
          report.skipped << { entry: entry, reason: "ligne affectée en partie : à regarder à la main" }
        end
      end
    end

    # Ligne encore à affecter : le règlement ET l'affectation en 400000.
    def link(entry, paid_months, report)
      report.links << { entry: entry, months: paid_months, amount_cents: entry.amount_cents, status: :new }
      return unless @apply

      Finance::RecordMemberSettlement.new(member_account: @account, cash_entry: entry, flow: @charge.flow,
                                          whodunnit: @whodunnit).run!
    end

    # Ligne déjà comptabilisée : le compte courant seul, un règlement par mois.
    def settle(entry, month, unit, report)
      key = "rattrapage:charge-#{@charge.id}:cash_entry:#{entry.id}:#{month.strftime('%Y-%m')}"
      if AccountEntry.unscoped.exists?(idempotency_key: key)
        return report.settlements << { entry: entry, month: month, amount_cents: unit, status: :existing }
      end

      report.settlements << { entry: entry, month: month, amount_cents: unit, status: :new }
      return unless @apply

      Finance::RecordSettlement.new(
        member_account: @account, amount_cents: unit, received_on: entry.entry_date,
        method: "bank_transfer", received_channel: "bank",
        reference: "reprise-#{@charge.flow}:#{month.strftime('%Y-%m')}",
        notes: "#{@charge.label} — #{entry.communication.presence || entry.label} " \
               "(ligne de trésorerie ##{entry.id}, déjà comptabilisée). Rattrapage du #{I18n.l(Date.current)}.",
        flow: @charge.flow, whodunnit: @whodunnit, idempotency_key: key
      ).run!
    end

    # Les mois payés sans facture en face, et l'inverse : c'est ce qui dit si la
    # date de début de la règle est la bonne.
    def compare(report)
      billed = report.charges.map { |c| c[:month] }.to_set
      paid = (report.settlements.map { |s| s[:month] } + report.links.flat_map { |l| l[:months] }).tally

      report.paid_unbilled = paid.keys.reject { |m| billed.include?(m) }.sort
      report.billed_unpaid = billed.reject { |m| paid.key?(m) }.sort
    end

    def money(cents) = Money.new(cents, "EUR").format
  end
end
