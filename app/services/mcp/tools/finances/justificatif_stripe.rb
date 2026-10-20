module Mcp
  module Tools
    module Finances
      # Comptabilité > Coût d'encaissement > justificatifs (StripeFeeInvoicesController) :
      # déclarer ce que Stripe facture en frais pour un mois, face à ce que
      # Claudy a compté. Aucune écriture comptable n'en découle. Le PDF, lui, se
      # dépose à l'écran : le connecteur ne transporte pas de fichier.
      class JustificatifStripe < Ecriture
        include Commun

        tool "justificatif_stripe",
             title: "Justificatif mensuel des frais Stripe",
             description: "Déclare le justificatif des frais Stripe d'un mois pour un compte (montant facturé par " \
                          "Stripe, référence, notes) ou le retire (geste retirer). L'écart avec les frais comptés par " \
                          "Claudy se lit dans cout_encaissement. Aucune écriture comptable. Le PDF se joint à l'écran " \
                          "« Coût d'encaissement » ; une déclaration le garde s'il y en a déjà un.",
             schema: {
               properties: {
                 geste: { type: "string", enum: %w[declarer retirer], description: "declarer (défaut) ou retirer." },
                 compte: { type: "string", description: "Le compte Stripe : #{StripeService::ACCOUNTS.map { |cle, v| "#{cle} (#{v[:label]})" }.join(', ')}." },
                 mois: MOIS,
                 montant: MONTANT.merge(description: "Les frais facturés par Stripe ce mois-là, en euros."),
                 reference: { type: "string", description: "Numéro de la facture Stripe." },
                 notes: { type: "string" }
               },
               required: %w[compte mois]
             }

        private

        def planifier(arguments)
          cle = compte_stripe!(arguments["compte"])
          mois = mois!(arguments["mois"])
          existant = StripeFeeInvoice.find_for(cle, mois)
          libelle = "#{StripeService.label_for(cle)}, #{nom_mois(mois)}"

          if arguments["geste"].to_s == "retirer"
            raise Error, "Aucun justificatif pour #{libelle}." if existant.nil?

            return Plan.new(resume: "Retirer le justificatif de #{libelle} : #{ligne(existant)}",
                            empreinte: [etat_de(existant)], donnees: { geste: "retirer", id: existant.id })
          end

          attributs = {}
          attributs[:declared_fee_cents] = cents!(arguments["montant"], "montant").abs if arguments["montant"].present?
          attributs[:reference] = arguments["reference"].to_s.strip.presence if arguments.key?("reference")
          attributs[:notes] = arguments["notes"].to_s.strip.presence if arguments.key?("notes")
          raise Error, "Donne au moins le montant facturé par Stripe." if attributs.empty?

          resume = existant ? "Corriger le justificatif de #{libelle} : #{ligne(existant)}" : "Nouveau justificatif pour #{libelle}"
          resume += "\nMontant déclaré : #{euros(attributs[:declared_fee_cents])}" if attributs[:declared_fee_cents]
          Plan.new(resume: resume, empreinte: [existant && etat_de(existant), attributs.transform_values(&:to_s).sort],
                   donnees: { geste: "declarer", cle: cle, mois: mois.iso8601, attributs: attributs })
        end

        def appliquer(plan)
          d = plan.donnees
          if d[:geste] == "retirer"
            justificatif = StripeFeeInvoice.find(d[:id])
            justificatif.soft_delete!(validate: false)
            return "Justificatif retiré."
          end

          mois = Date.iso8601(d[:mois])
          justificatif = StripeFeeInvoice.find_for(d[:cle], mois) || StripeFeeInvoice.new(account_key: d[:cle], period_month: mois)
          metier! { justificatif.update!(d[:attributs]) }
          "Justificatif enregistré : #{ligne(justificatif)}. L'écart se lit dans cout_encaissement."
        end

        def ligne(justificatif)
          [("déclaré #{euros(justificatif.declared_fee_cents)}#{' (relevé chez Stripe)' if justificatif.fetched_from_stripe?}" if justificatif.declared_fee_cents),
           ("réf. #{justificatif.reference}" if justificatif.reference.present?),
           ("PDF déposé" if justificatif.document.attached?)].compact.join(" · ").presence || "vide"
        end

        def compte_stripe!(reference)
          texte = I18n.transliterate(reference.to_s.strip).downcase
          cle, = StripeService::ACCOUNTS.find do |k, v|
            k.to_s == texte.tr(" ", "_") || I18n.transliterate(v[:label]).downcase == texte
          end
          cle&.to_s || raise(Error, "Compte Stripe inconnu « #{reference} » : #{StripeService::ACCOUNTS.keys.join(', ')}.")
        end
      end
    end
  end
end
