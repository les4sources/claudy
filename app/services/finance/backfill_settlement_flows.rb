module Finance
  # Repose sur chaque règlement historique le POSTE qu'il éteint (issue #349
  # bis, Michael 2026-09-20).
  #
  # `RecordSettlement` écrivait `flow: "other"` sur toutes les écritures de
  # règlement : le grand livre savait qu'un virement de 345 € était arrivé, pas
  # qu'il payait les charges. `MemberAccounts::Outstanding` imputait donc tous
  # postes confondus, et une famille voyait ses charges du mois réclamées alors
  # qu'elle venait de les verser.
  #
  # Le poste n'est pas deviné : il se lit dans la RÉFÉRENCE que la reprise
  # comptable a laissée sur chaque `AccountSettlement`, et à défaut dans le
  # motif écrit dans ses notes. Ce qui ne se lit ni dans l'une ni dans l'autre
  # reste « Divers » et sort dans le rapport — on préfère un poste vide qu'un
  # poste faux, parce qu'un règlement rangé au mauvais endroit crée une dette
  # imaginaire d'un côté et une avance imaginaire de l'autre.
  class BackfillSettlementFlows < ServiceBase
    Report = Struct.new(:updated, :skipped, :untouched, keyword_init: true) do
      def any? = updated.any? || skipped.any?
    end

    # Du plus précis au plus général. La première expression qui matche gagne,
    # donc l'ordre compte : `reprise-charges` avant tout motif contenant
    # « charges ».
    PAR_REFERENCE = [
      [/\Areprise-bar/, "bar"],
      [/\Areprise-restauration/, "meal"],
      [/\Areprise-charges/, "charges"],
      [/\Abanque-2026:.*:(charges-habitants|loyer)\z/, "charges"]
    ].freeze

    PAR_MOTIF = [
      [/poulet|épicerie|epicerie/i, "grocery"],
      [/\bbar\b/i, "bar"],
      [/batch ?cooking|repas/i, "meal"],
      # « Solde frais février 2026 » est un complément de charges : le motif
      # dit « frais », pas « frais mensuels ».
      [/loyer|frais|charges|participation famille/i, "charges"]
    ].freeze

    def initialize(dry_run: true, whodunnit: nil)
      @dry_run = dry_run
      @whodunnit = whodunnit
    end

    def run = catch_error { backfill }
    def run! = backfill

    private

    def backfill
      report = Report.new(updated: [], skipped: [], untouched: 0)

      PaperTrail.request(whodunnit: @whodunnit || "backfill-settlement-flows") do
        AccountSettlement.includes(:account_entry).find_each do |settlement|
          entry = settlement.account_entry
          # Une écriture déjà rangée dans un poste ne se rejoue pas : la tâche
          # doit pouvoir tourner deux fois sans rien changer la seconde.
          next report.untouched += 1 if entry.nil? || entry.flow.present? && entry.flow != "other"

          flow = poste_pour(settlement)
          next report.skipped << settlement if flow.nil?

          report.updated << { settlement: settlement, flow: flow }
          entry.update!(flow: flow) unless @dry_run
        end
      end

      report
    end

    def poste_pour(settlement)
      reference = settlement.reference.to_s
      trouve = PAR_REFERENCE.find { |motif, _| reference.match?(motif) }
      return trouve.last if trouve

      texte = "#{settlement.notes} #{reference}"
      PAR_MOTIF.find { |motif, _| texte.match?(motif) }&.last
    end
  end
end
