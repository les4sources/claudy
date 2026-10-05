module Mcp
  module Tools
    # La seule correction possible d'une ligne verrouillée : une ligne de
    # montant opposé qui pointe vers l'originale. L'originale ne bouge pas.
    class ContrePasserLignes < Ecriture
      tool "contre_passer_lignes",
           title: "Contre-passer des lignes",
           description: "Annule des lignes par une contre-écriture (montant opposé, même poste, liée à l'originale), " \
                        "sans toucher l'originale. Obligatoire pour une ligne verrouillée par un décompte émis ; " \
                        "préférable quand la ligne a déjà été vue par la famille.",
           schema: {
             properties: {
               compte: COMPTE,
               lignes: { type: "array", items: { type: "integer" }, description: "Identifiants des lignes (#id)." },
               date: DATE.merge(description: "Date des contre-écritures (AAAA-MM-JJ). Aujourd'hui par défaut.")
             },
             required: %w[compte lignes motif]
           }

      private

      def planifier(arguments)
        motif = motif!(arguments)
        compte = compte!(arguments["compte"])
        date = date_ou_nil(arguments["date"], "date") || Date.current
        ids = ids!(arguments["lignes"])
        entries = compte.account_entries.where(id: ids).includes(:reversal, :account_settlement).order(:entry_date, :id).to_a

        manquantes = ids - entries.map(&:id)
        raise Error, "Lignes introuvables sur #{compte.code} : #{manquantes.map { |id| "##{id}" }.join(', ')}." if manquantes.any?

        deja = entries.select(&:reversal)
        if deja.any?
          raise Error, "Déjà contre-passées : #{deja.map { |e| "##{e.id} (par ##{e.reversal.id})" }.join(', ')}."
        end

        nouvelles = entries.map do |entry|
          { member_account_id: compte.id, entry_date: date, posted_at: Time.current, amount_cents: -entry.amount_cents,
            kind: "reversal", reversal_of_id: entry.id, flow: entry.flow, source: entry.source,
            label: "Contre-écriture — #{entry.label} (#{motif})".first(250) }
        end

        avant = postes_dus(compte)
        apres = reste_du_apres([compte]) { AccountEntry.create!(nouvelles) }
        Plan.new(
          resume: "#{compte.code} — #{compte.name} : #{entries.size} contre-écriture(s) datée(s) du #{date}\n" \
                  "#{entries.map { |e| "  annule #{ligne(e)}" }.join("\n")}\n\n" \
                  "Avant : #{avant}\nAprès : #{apres[compte.id]}",
          empreinte: [compte.id, date.iso8601, entries.map { |e| [e.id, e.amount_cents] }],
          donnees: { compte: compte, nouvelles: nouvelles }
        )
      end

      def appliquer(plan)
        creees = AccountEntry.create!(plan.donnees[:nouvelles].map { |attrs| attrs.merge(posted_at: Time.current) })
        compte = plan.donnees[:compte].reload
        "Contre-écritures passées : #{creees.map { |e| "##{e.id} (annule ##{e.reversal_of_id})" }.join(', ')}. " \
          "Reste dû sur #{compte.code} : #{postes_dus(compte)}"
      end
    end
  end
end
