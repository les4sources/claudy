module Mcp
  module Tools
    # Un paiement reçu, encodé comme depuis l'écran « Règlements » : un seul
    # règlement, une ligne par poste payé (`Finance::RecordSettlement`).
    class EncoderReglement < Ecriture
      tool "encoder_reglement",
           title: "Encoder un règlement",
           description: "Enregistre un paiement reçu d'un compte (virement, espèces, compensation), sur un poste ou " \
                        "ventilé sur plusieurs. Une référence « reprise-<poste>:AAAA-MM » fait payer CE mois-là " \
                        "plutôt que la dette la plus ancienne.",
           schema: {
             properties: {
               compte: COMPTE,
               montant: { type: %w[number string], description: "Montant reçu en euros, positif." },
               recu_le: DATE.merge(description: "Date de réception (AAAA-MM-JJ)."),
               poste: POSTE.merge(description: "Poste payé, si un seul. #{POSTE[:description]}"),
               ventilation: { type: "object", additionalProperties: { type: %w[number string] },
                              description: "Répartition sur plusieurs postes, en euros : {\"charges\": 230, \"dome\": 50}. " \
                                           "La somme doit valoir le montant." },
               methode: { type: "string", enum: AccountSettlement::METHODS, description: "bank_transfer par défaut." },
               canal: { type: "string", enum: AccountSettlement::CHANNELS, description: "Où l'argent est arrivé. bank par défaut." },
               reference: { type: "string", description: "Communication du virement, ou « reprise-bar:2026-05 » pour viser un mois." },
               notes: { type: "string" }
             },
             required: %w[compte montant recu_le]
           }

      private

      def planifier(arguments)
        compte = compte!(arguments["compte"])
        cents = cents!(arguments["montant"], "montant").abs
        recu_le = date!(arguments["recu_le"], "recu_le")
        ventilation = arguments["ventilation"].presence&.to_h { |poste, montant| [poste!(poste), cents!(montant, "ventilation #{poste}").abs] }
        flow = arguments["poste"].present? ? poste!(arguments["poste"]) : nil
        raise Error, "Donne un poste ou une ventilation : un règlement sans poste tombe dans « Divers »." if flow.nil? && ventilation.nil?
        if ventilation && ventilation.values.sum != cents
          raise Error, "La ventilation totalise #{euros(ventilation.values.sum)} pour un règlement de #{euros(cents)}."
        end

        options = {
          amount_cents: cents, received_on: recu_le, flow: flow, ventilation: ventilation,
          method: arguments["methode"].presence || "bank_transfer", received_channel: arguments["canal"].presence || "bank",
          reference: arguments["reference"].to_s.strip.presence, notes: arguments["notes"].to_s.strip.presence
        }
        cle = "claude-reglement:#{Digest::SHA256.hexdigest([compte.id, options].to_json).first(24)}"
        if AccountEntry.with_deleted { AccountEntry.where("idempotency_key LIKE ?", "#{cle}%").exists? }
          raise Error, "Ce règlement a déjà été encodé (même compte, montant, date, poste et référence)."
        end
        options[:idempotency_key] = cle

        doublons = compte.account_settlements.where(amount_cents: cents, received_on: (recu_le - 3)..(recu_le + 3)).to_a
        avant = postes_dus(compte)
        apres = reste_du_apres([compte]) { enregistrer(compte, options) }
        repartition = (ventilation || { flow => cents }).map { |poste, montant| "#{AccountEntry::FLOW_LABELS[poste]} #{euros(montant)}" }
        avertissement = doublons.map do |s|
          "\n⚠ Un règlement de #{euros(s.amount_cents)} reçu le #{s.received_on} existe déjà sur ce compte (« #{s.reference} ») : doublon ?"
        end.join

        Plan.new(
          resume: "#{compte.code} — #{compte.name} : règlement de #{euros(cents)} reçu le #{recu_le} " \
                  "(#{AccountSettlement::METHOD_LABELS[options[:method]]}, #{AccountSettlement::CHANNEL_LABELS[options[:received_channel]]})\n" \
                  "  Postes : #{repartition.join(', ')}#{"\n  Référence : #{options[:reference]}" if options[:reference]}" \
                  "#{avertissement}\n\nAvant : #{avant}\nAprès : #{apres[compte.id]}",
          empreinte: [compte.id, options.transform_values(&:to_s)],
          donnees: { compte: compte, options: options }
        )
      end

      def appliquer(plan)
        compte = plan.donnees[:compte]
        reglement = enregistrer(compte, plan.donnees[:options])
        "Règlement ##{reglement.id} encodé sur #{compte.code}. Reste dû : #{postes_dus(compte.reload)}"
      end

      def enregistrer(compte, options)
        Finance::RecordSettlement.new(member_account: compte, whodunnit: whodunnit, **options).run!
      end
    end
  end
end
