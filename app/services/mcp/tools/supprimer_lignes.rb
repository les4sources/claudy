module Mcp
  module Tools
    # `correction-frennet.rb` : retirer des lignes facturées à tort. C'est une
    # suppression DOUCE (soft delete) : la ligne disparaît des comptes mais
    # reste en base, et PaperTrail garde qui l'a retirée et pourquoi.
    class SupprimerLignes < Ecriture
      tool "supprimer_lignes",
           title: "Supprimer des lignes",
           description: "Retire d'un compte des lignes facturées à tort (double facturation, ligne qui n'aurait " \
                        "jamais dû exister). Suppression douce, tracée. Refuse une ligne verrouillée par un décompte " \
                        "émis : utilise alors contre_passer_lignes.",
           schema: {
             properties: {
               compte: COMPTE,
               lignes: { type: "array", items: { type: "integer" }, description: "Identifiants des lignes (#id)." }
             },
             required: %w[compte lignes motif]
           }

      private

      def planifier(arguments)
        motif!(arguments)
        compte = compte!(arguments["compte"])
        ids = ids!(arguments["lignes"])
        entries = compte.account_entries.where(id: ids).includes(:account_settlement).order(:entry_date, :id).to_a

        manquantes = ids - entries.map(&:id)
        raise Error, "Lignes introuvables sur #{compte.code} (déjà supprimées ou d'un autre compte) : #{manquantes.map { |id| "##{id}" }.join(', ')}." if manquantes.any?

        verrouillees = entries.select(&:locked?)
        if verrouillees.any?
          raise Error, "Ces lignes sont verrouillées par un décompte émis et ne se suppriment pas : " \
                       "#{verrouillees.map { |e| "##{e.id}" }.join(', ')}. Utilise contre_passer_lignes."
        end

        avant = postes_dus(compte)
        apres = reste_du_apres([compte]) { supprimer(entries) }
        Plan.new(
          resume: "#{compte.code} — #{compte.name} : #{entries.size} ligne(s) à supprimer, " \
                  "#{euros(entries.sum(&:amount_cents))} au total\n" \
                  "#{entries.map { |e| "  #{ligne(e)}" }.join("\n")}\n\n" \
                  "Avant : #{avant}\nAprès : #{apres[compte.id]}",
          empreinte: [compte.id, entries.map { |e| [e.id, e.amount_cents] }],
          donnees: { compte: compte, entries: entries }
        )
      end

      def appliquer(plan)
        supprimer(plan.donnees[:entries])
        compte = plan.donnees[:compte].reload
        "#{plan.donnees[:entries].size} ligne(s) supprimée(s) sur #{compte.code}. Reste dû : #{postes_dus(compte)}"
      end

      def supprimer(entries)
        entries.each { |entry| AccountEntry.find(entry.id).soft_delete!(validate: false) }
      end
    end
  end
end
