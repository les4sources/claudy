module Mcp
  module Tools
    # Une ligne libre : un rattrapage oublié, un avoir, une régularisation.
    # Le montant est signé comme dans le grand livre.
    class PasserEcriture < Ecriture
      tool "passer_ecriture",
           title: "Passer une écriture",
           description: "Ajoute une ligne à un compte : montant POSITIF = le compte doit (rattrapage d'une " \
                        "consommation oubliée), NÉGATIF = en sa faveur (avoir, geste, régularisation). Pour annuler " \
                        "une ligne précise, préfère contre_passer_lignes ; pour un paiement reçu, encoder_reglement.",
           schema: {
             properties: {
               compte: COMPTE,
               date: DATE.merge(description: "Date de l'écriture (AAAA-MM-JJ). Elle décide du mois qu'elle touche."),
               montant: { type: %w[number string], description: "En euros, signé : 12.50 ou \"-92,17\"." },
               poste: POSTE,
               libelle: { type: "string", description: "Libellé lu par la famille sur son compte." },
               type: { type: "string", description: "Type de ligne (bar, grocery, meal, recurring, reversal…). " \
                                                    "Par défaut : reversal pour un crédit, le poste pour un débit." }
             },
             required: %w[compte date montant poste libelle motif]
           }

      private

      def planifier(arguments)
        motif!(arguments)
        compte = compte!(arguments["compte"])
        cents = cents!(arguments["montant"], "montant")
        flow = poste!(arguments["poste"])
        libelle = arguments["libelle"].to_s.strip.presence || raise(Error, "Donne un libellé.")
        attrs = {
          member_account_id: compte.id, entry_date: date!(arguments["date"], "date"), amount_cents: cents, flow: flow,
          kind: arguments["type"].presence || (cents.negative? ? "reversal" : (AccountEntry::KINDS.include?(flow) ? flow : nil)),
          source: "claude", label: libelle.first(250)
        }
        cle = "claude-ecriture:#{Digest::SHA256.hexdigest(attrs.to_json).first(24)}"
        if (existante = AccountEntry.with_deleted { AccountEntry.find_by(idempotency_key: cle) })
          raise Error, "Cette écriture a déjà été passée : ##{existante.id}. Change le libellé si tu en veux vraiment une seconde."
        end

        attrs[:idempotency_key] = cle
        avant = postes_dus(compte)
        apres = reste_du_apres([compte]) { AccountEntry.create!(attrs.merge(posted_at: Time.current)) }
        Plan.new(
          resume: "#{compte.code} — #{compte.name} : nouvelle ligne\n" \
                  "  #{attrs[:entry_date]}  #{euros(cents)}  #{AccountEntry::FLOW_LABELS[flow]} · #{AccountEntry::KIND_LABELS.fetch(attrs[:kind], attrs[:kind]) || '—'}  #{libelle}\n\n" \
                  "Avant : #{avant}\nAprès : #{apres[compte.id]}",
          empreinte: attrs.transform_values(&:to_s),
          donnees: { compte: compte, attrs: attrs }
        )
      end

      def appliquer(plan)
        entry = AccountEntry.create!(plan.donnees[:attrs].merge(posted_at: Time.current))
        compte = plan.donnees[:compte].reload
        "Ligne ##{entry.id} passée sur #{compte.code}. Reste dû : #{postes_dus(compte)}"
      end
    end
  end
end
