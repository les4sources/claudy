module Mcp
  module Tools
    module Finances
      # Comptabilité > Feuille de caisse (CashSheetController#show) : les
      # lignes d'un mois avec le solde courant, comme sur la feuille papier.
      class FeuilleDeCaisse < Base
        include Commun

        tool "feuille_de_caisse",
             title: "Feuille de caisse",
             description: "Les entrées et sorties d'espèces d'un mois : solde d'ouverture, chaque ligne (#id, date, " \
                          "motif, montant, solde après), solde de clôture, lignes retirées et leur motif, et si le " \
                          "mois est arrêté. Les motifs de caisse sont listés par referentiel_comptable.",
             schema: {
               properties: {
                 mois: MOIS.merge(description: "Mois, AAAA-MM. Défaut : le mois en cours."),
                 caisse: { type: "string", description: "La caisse, s'il y en a plusieurs." }
               }
             }

        def call(arguments)
          caisse = caisse!(arguments["caisse"])
          feuille = ::Finance::CashSheet.new(cash_account: caisse, month: mois!(arguments["mois"], defaut: Date.current.beginning_of_month))
          lignes = feuille.rows.map do |row|
            e = row.entry
            "##{e.id}  #{e.entry_date}  #{e.cash_motif&.label || e.cash_allocations.first&.general_account&.code || '—'} · #{e.label}" \
              "#{" (#{e.notes.squish.truncate(60)})" if e.notes.present?}  #{euros(e.amount_cents).rjust(11)}  → #{euros(row.balance_cents)}"
          end
          retirees = feuille.excluded_entries.map { |e| "##{e.id} #{e.entry_date} #{e.label} #{euros(e.amount_cents)} — #{e.excluded_reason}" }

          [
            "#{caisse.name} — #{nom_mois(feuille.month)}#{' (MOIS ARRÊTÉ : plus de saisie)' if feuille.closed?}",
            "Ouverture : #{euros(feuille.opening_cents)} · entrées #{euros(feuille.incoming_cents)} · sorties " \
            "#{euros(feuille.outgoing_cents.abs)} · clôture #{euros(feuille.closing_cents)}",
            lignes.presence&.join("\n") || "Aucune ligne ce mois-ci.",
            ("Retirées :\n#{retirees.join("\n")}" if retirees.any?)
          ].compact.join("\n")
        end
      end
    end
  end
end
