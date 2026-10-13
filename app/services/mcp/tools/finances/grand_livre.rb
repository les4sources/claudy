module Mcp
  module Tools
    module Finances
      # Comptabilité > États > Grand livre (LedgerController#index) : les
      # écritures d'un compte du plan sur une période, avec le solde d'ouverture
      # et le solde courant après chaque ligne.
      class GrandLivre < Base
        include Commun

        LIMITE = 150

        tool "grand_livre",
             title: "Grand livre d'un compte",
             description: "Les écritures passées sur un compte du plan comptable, de date à date (défaut : l'année " \
                          "civile) : solde d'ouverture, chaque ligne (date, journal et n° d'écriture, libellé, débit, " \
                          "crédit, solde courant), solde de clôture. Filtrable par entité. Un solde positif est " \
                          "débiteur.",
             schema: {
               properties: {
                 compte: COMPTE_GENERAL,
                 entite: ENTITE.merge(description: "Facultatif : une seule entité."),
                 du: DATE, au: DATE
               },
               required: %w[compte]
             }

        def call(arguments)
          compte = compte_du_plan!(arguments["compte"])
          entite = arguments["entite"].present? ? entite!(arguments["entite"]) : nil
          du, au = periode!(arguments)

          base = JournalLine.joins(:journal_entry).where(general_account_id: compte.id)
          base = base.where(journal_entries: { legal_entity_id: entite.id }) if entite
          ouverture = base.where("journal_entries.entry_date < ?", du)
          solde = ouverture.sum(:debit_cents) - ouverture.sum(:credit_cents)
          lignes = base.where(journal_entries: { entry_date: du..au })
                       .includes(journal_entry: :fiscal_year)
                       .order("journal_entries.entry_date", "journal_entries.id").to_a

          sortie = ["#{compte}#{" · #{entite.name}" if entite} · du #{du} au #{au}",
                    "Solde d'ouverture : #{solde_lisible(solde)}"]
          courant = solde
          detail = lignes.map do |l|
            courant += l.signed_cents
            e = l.journal_entry
            "#{e.entry_date} · #{e.reference} · #{(l.label.presence || e.label).to_s.truncate(70)} · " \
              "#{l.debit_cents.positive? ? "débit #{euros(l.debit_cents)}" : "crédit #{euros(l.credit_cents)}"} · solde #{euros(courant)}"
          end
          sortie += detail.last(LIMITE)
          sortie.insert(2, "… #{detail.size - LIMITE} lignes plus anciennes : resserre la période.") if detail.size > LIMITE
          sortie << "Aucune écriture sur la période." if lignes.empty?
          sortie << "Mouvements : débit #{euros(lignes.sum(&:debit_cents))} · crédit #{euros(lignes.sum(&:credit_cents))}"
          sortie << "Solde de clôture : #{solde_lisible(courant)}"
          sortie.join("\n")
        end

        private

        # Le grand livre se lit aussi sur un compte désactivé : on accepte son
        # code exact avant de chercher parmi les comptes actifs.
        def compte_du_plan!(reference)
          GeneralAccount.find_by(code: reference.to_s.strip) || compte_general!(reference)
        end
      end
    end
  end
end
