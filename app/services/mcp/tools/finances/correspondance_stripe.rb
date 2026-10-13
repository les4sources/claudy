module Mcp
  module Tools
    module Finances
      # Comptabilité > Stripe > correspondances (StripeCategoryMappingsController) :
      # où va une catégorie de ventes Stripe d'un compte en mode grand livre.
      # Retirer est doux (soft-delete) : les lignes déjà affectées gardent la leur.
      class CorrespondanceStripe < Ecriture
        include Commun

        GESTES = %w[creer modifier retirer].freeze

        tool "correspondance_stripe",
             title: "Correspondance d'une catégorie Stripe",
             description: "Dit où va une catégorie de ventes Stripe (ex. « pain » → 700100, pôle Épicerie) sur un " \
                          "compte en mode grand livre : creer, modifier ou retirer. Une catégorie vide vaut « sans " \
                          "catégorie ». Les lignes déjà affectées gardent l'affectation qu'elles ont reçue. Les " \
                          "correspondances (#id) et les catégories non couvertes : comptes_stripe.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES },
                 correspondance: { type: %w[integer string], description: "Pour modifier ou retirer : la correspondance (#id)." },
                 compte: { type: "string", description: "Pour creer : le compte de trésorerie Stripe (nom)." },
                 categorie: { type: "string", description: "La catégorie Stripe, telle qu'elle apparaît dans comptes_stripe. Vide : sans catégorie." },
                 compte_general: COMPTE_GENERAL,
                 pole: { type: "string", description: "Pôle (nom). « aucun » pour le retirer." },
                 entite: { type: "string", description: "Entité juridique (nom). « aucune » : celle du compte Stripe." },
                 notes: { type: "string" }
               },
               required: %w[geste]
             }

        private

        def planifier(arguments)
          geste = arguments["geste"].to_s
          raise Error, "geste : #{GESTES.join(', ')}." unless GESTES.include?(geste)

          correspondance = geste == "creer" ? nil : correspondance!(arguments["correspondance"])
          if geste == "retirer"
            return Plan.new(resume: "Retirer : #{ligne(correspondance)}\nLes lignes déjà affectées gardent la leur ; " \
                                    "les prochaines transactions de cette catégorie resteront « à affecter ».",
                            empreinte: [etat_de(correspondance)], donnees: { geste: geste, id: correspondance.id })
          end

          attributs = attributs!(arguments, correspondance)
          raise Error, "Rien à changer." if correspondance && attributs.empty?

          apres = simuler { ecrire(correspondance&.id, attributs) }
          resume = correspondance ? "Modifier : #{ligne(correspondance)}\nAprès : #{apres}" : "Nouvelle correspondance : #{apres}"
          Plan.new(resume: resume, empreinte: [correspondance && etat_de(correspondance), attributs.transform_values(&:to_s).sort],
                   donnees: { geste: geste, id: correspondance&.id, attributs: attributs })
        end

        def appliquer(plan)
          d = plan.donnees
          if d[:geste] == "retirer"
            correspondance = StripeCategoryMapping.find(d[:id])
            correspondance.soft_delete!
            return "Correspondance retirée : #{ligne(correspondance)}"
          end

          "Correspondance enregistrée : #{ecrire(d[:id], d[:attributs])}"
        end

        def ecrire(id, attributs)
          correspondance = id ? StripeCategoryMapping.find(id) : StripeCategoryMapping.new
          metier! { correspondance.update!(attributs) }
          ligne(correspondance.reload)
        end

        def ligne(m)
          "##{m.id || 'nouvelle'} #{StripeService.label_for(m.account_key)} · #{m.category_label} → #{m.general_account}" \
            "#{" · pôle #{m.team.name}" if m.team}#{" · #{m.legal_entity.name}" if m.legal_entity}" \
            "#{" · #{m.notes.squish.truncate(60)}" if m.notes.present?}"
        end

        def correspondance!(reference)
          raise Error, "Donne la correspondance (#id, rendu par comptes_stripe)." if reference.blank?

          StripeCategoryMapping.includes(:general_account, :team, :legal_entity).find_by(id: id!(reference, "correspondance")) ||
            raise(Error, "Aucune correspondance Stripe ##{reference.to_s.delete('#')}.")
        end

        def attributs!(arguments, correspondance)
          a = {}
          if correspondance.nil?
            compte = par_nom!(CashAccount.stripe, arguments["compte"], "compte Stripe")
            raise Error, "#{compte.name} n'a pas de clé de compte Stripe." if compte.stripe_account_key.blank?
            raise Error, "#{compte.name} est en mode « #{compte.stripe_mode_label} » : les correspondances ne servent qu'en grand livre (mode_stripe)." unless compte.ledger?

            a[:account_key] = compte.stripe_account_key
            a[:category] = arguments["categorie"].to_s.strip.presence
            raise Error, "Donne le compte_general." if arguments["compte_general"].blank?
          elsif arguments.key?("categorie")
            a[:category] = arguments["categorie"].to_s.strip.presence
          end
          a[:general_account_id] = compte_general!(arguments["compte_general"]).id if arguments["compte_general"].present?
          if arguments["pole"].present?
            a[:team_id] = arguments["pole"].to_s.strip.casecmp?("aucun") ? nil : pole!(arguments["pole"]).id
          end
          if arguments["entite"].present?
            a[:legal_entity_id] = arguments["entite"].to_s.strip.casecmp?("aucune") ? nil : entite!(arguments["entite"]).id
          end
          a[:notes] = arguments["notes"].to_s.strip.presence if arguments.key?("notes")
          a
        end
      end
    end
  end
end
