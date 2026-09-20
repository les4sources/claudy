module Finance
  # Répare le décalage d'un mois hérité de la reprise comptable (issue #354).
  #
  # Deux foyers avaient versé leur virement de janvier 2026 en décembre 2025 ;
  # la reprise l'a attribué à la charge de décembre, et la charge de janvier
  # est restée ouverte. Il manque l'écriture, pas l'argent — la correction
  # encode le règlement à SA date réelle, le 31 décembre, pour que le lettrage
  # FIFO de `MemberAccounts::Outstanding` l'impute sur la charge de janvier dès
  # qu'elle se présente.
  #
  # TROIS REFUS PLUTÔT QU'UNE APPROXIMATION :
  #
  # 1. Le montant se lit au grand livre — la charge de janvier de CE compte.
  #    Passer le montant en paramètre reviendrait à retaper à la main ce que le
  #    livre sait déjà, avec le risque d'un centime d'écart qui créerait un
  #    second trou. Un compte sans exactement une charge de janvier est refusé.
  # 2. Le compte doit avoir le SYMPTÔME : son écart cumulé de charges doit
  #    couvrir au moins la charge de janvier. On ne corrige pas un compte à
  #    jour, même si quelqu'un l'a nommé par erreur sur la ligne de commande.
  # 3. Rejouer ne crée rien : la `reference` sert de garde, doublée de
  #    l'`idempotency_key` de l'écriture, que l'index d'unicité refuse en base.
  #
  # Rien n'est écrit sans `dry_run: false` — la tâche se lance à la main, par
  # quelqu'un qui a lu le dry-run.
  class FixJanuaryOffset < ServiceBase
    FLOW = MemberChargesAudit::FLOW

    Planned = Struct.new(:account, :amount_cents, :received_on, :reference, keyword_init: true)
    Refusal = Struct.new(:code, :account, :reason, keyword_init: true)

    Report = Struct.new(:created, :planned, :existing, :refused, keyword_init: true) do
      def total_cents = planned.sum(&:amount_cents)
      def any? = planned.any? || existing.any? || refused.any?
    end

    def initialize(codes:, year: Date.current.year, dry_run: true, whodunnit: nil)
      @codes = Array(codes).flat_map { |code| code.to_s.split(",") }.map(&:strip).reject(&:empty?)
      @year = year.to_i
      @dry_run = dry_run
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { year: @year, codes: @codes }) { fix }
    end

    def run! = fix

    # Le 31 décembre de l'année précédente : la date à laquelle l'argent est
    # réellement parti du compte du foyer.
    def received_on = Date.new(@year - 1, 12, 31)

    def reference_for(code) = "reprise-offset:#{code}:#{format('%04d-01', @year)}"

    private

    def fix
      report = Report.new(created: [], planned: [], existing: [], refused: [])
      return report if @codes.empty?

      audit = MemberChargesAudit.new(year: @year, codes: @codes)

      @codes.each { |code| process(code, audit, report) }
      report
    end

    def process(code, audit, report)
      account = MemberAccount.find_by(code: code)
      return report.refused << Refusal.new(code: code, reason: "compte introuvable") if account.nil?

      # La garde d'idempotence passe AVANT les refus : une fois la correction
      # écrite, le compte n'a plus le symptôme, et rejouer dirait « pas de
      # symptôme » là où la vérité est « déjà corrigé ».
      reference = reference_for(code)
      done = AccountSettlement.unscoped.find_by(reference: reference)
      if done
        return report.existing << Planned.new(account: account, reference: reference,
                                              received_on: done.received_on,
                                              amount_cents: done.amount_cents)
      end

      reason = refusal_for(account, audit)
      return report.refused << Refusal.new(code: code, account: account, reason: reason) if reason

      write(account, audit.audit_for(account), reference, report)
    end

    def refusal_for(account, audit)
      entry = audit.audit_for(account)
      return "aucune charge au grand livre en #{@year}" if entry.nil?
      return "aucune charge de janvier #{@year}" if entry.january_charges.empty?

      unless entry.single_january_charge?
        return "#{entry.january_charges.size} charges en janvier #{@year} — montant ambigu, " \
               "à trancher à la main plutôt qu'à approcher"
      end

      if entry.cumulative_cents < entry.january_charge_cents
        return "écart cumulé de #{euros(entry.cumulative_cents)} inférieur à la charge de janvier " \
               "(#{euros(entry.january_charge_cents)}) — ce compte n'a pas le symptôme"
      end

      nil
    end

    def write(account, entry, reference, report)
      planned = Planned.new(account: account, amount_cents: entry.january_charge_cents,
                            received_on: received_on, reference: reference)
      report.planned << planned
      return planned if @dry_run

      settlement = RecordSettlement.new(
        member_account: account,
        amount_cents: planned.amount_cents,
        received_on: received_on,
        method: "bank_transfer",
        received_channel: "bank",
        flow: FLOW,
        reference: reference,
        notes: notes_for(entry),
        whodunnit: @whodunnit || "reprise-offset",
        idempotency_key: reference
      ).run!

      report.created << settlement
      planned
    end

    # La note dit d'où vient la correction : dans six mois, une écriture de
    # 300 € au 31 décembre sans explication est indistinguable d'une erreur.
    def notes_for(entry)
      "Correction du décalage hérité de la reprise comptable d'août 2026 (issue #354). " \
        "Le virement de janvier #{@year} avait été versé en décembre #{@year - 1} et la reprise " \
        "l'a attribué à la charge de décembre ; la charge de janvier " \
        "(#{euros(entry.january_charge_cents)}) était restée ouverte. " \
        "Il manquait l'écriture, pas l'argent."
    end

    def euros(cents) = Money.new(cents, "EUR").format
  end
end
