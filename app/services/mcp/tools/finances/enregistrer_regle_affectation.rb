module Mcp
  module Tools
    module Finances
      # Comptabilité > Trésorerie > Règles d'affectation (AllocationRulesController
      # #create et #update) : créer ou corriger une règle. Elle PROPOSE, elle
      # n'affecte rien ; les lignes qu'elle reconnaît reçoivent sa suggestion,
      # qu'on accepte ensuite (accepter_suggestions, ou ligne par ligne).
      #
      # L'aperçu joue l'enregistrement pour de faux : il dit combien de lignes
      # recevront la suggestion, et en montre quelques-unes, avant qu'on décide.
      class EnregistrerRegleAffectation < Ecriture
        include Commun

        SENS = { "entree" => "incoming", "sortie" => "outgoing" }.freeze
        EXEMPLES = 8

        tool "enregistrer_regle_affectation",
             title: "Créer ou corriger une règle d'affectation",
             description: "Crée ou corrige une règle d'affectation : « quand une ligne ressemble à ceci, propose ce " \
                          "compte ». Au moins un critère (IBAN, tiers, communication, code, sens, montant) ; le compte " \
                          "de trésorerie restreint une règle mais ne suffit pas. La première règle qui reconnaît une " \
                          "ligne gagne : une règle précise passe avant une règle générale (ordre). Une règle passe " \
                          "avant Jev : ses propositions en attente sur ces lignes sont remplacées. L'aperçu dit combien " \
                          "de lignes « À affecter » recevront la suggestion. Rien n'est affecté : on accepte ensuite " \
                          "avec accepter_suggestions.",
             schema: {
               properties: {
                 regle: { type: %w[integer string], description: "Pour corriger : la règle (#id ou nom), rendue par regles_affectation. Absent : nouvelle règle." },
                 libelle: { type: "string", description: "Nom de la règle (ex. « Bar : paiements Payconiq »)." },
                 compte: COMPTE_GENERAL.merge(description: "Compte du plan proposé (701001, « bar »)."),
                 pole: POLE.merge(description: "Pôle proposé. Facultatif."),
                 entite: ENTITE.merge(description: "Entité qui porte l'affectation. Défaut : celle du compte de trésorerie, sinon la fondation."),
                 analytique: { type: "string", description: "Compte analytique proposé (code ou nom). Facultatif." },
                 evenement: { type: %w[integer string], description: "Événement (#id) dont c'est une recette. Facultatif." },
                 compte_tresorerie: { type: "string", description: "Limite la règle à ce compte (Triodos, Beobank, Caisse…). Facultatif." },
                 iban: { type: "string", description: "Critère : IBAN exact de la contrepartie." },
                 tiers_contient: { type: "string", description: "Critère : le nom de la contrepartie contient ce texte (sans casse)." },
                 communication_contient: { type: "string", description: "Critère : la communication contient ce texte (sans casse)." },
                 code_transaction: { type: "string", description: "Critère : le code de transaction bancaire commence par." },
                 sens: { type: "string", enum: SENS.keys, description: "Critère : entree (encaissements) ou sortie (décaissements)." },
                 min: MONTANT.merge(description: "Critère : montant minimal (valeur absolue)."),
                 max: MONTANT.merge(description: "Critère : montant maximal (valeur absolue)."),
                 confiance: { type: %w[integer string], description: "Confiance affichée, 0 à 100. Défaut : 80." },
                 ordre: { type: %w[integer string], description: "Position (petite = passe avant). Défaut : à la fin." },
                 active: { type: "boolean", description: "false pour désactiver la règle (ses suggestions en attente sont retirées)." }
               }
             }

        private

        def planifier(arguments)
          regle = arguments["regle"].present? ? regle!(arguments["regle"]) : nil
          attributs = attributs!(arguments, regle)
          raise Error, "Rien à changer." if regle && attributs.empty?

          resultat = simuler { appliquer_regle(regle&.id, attributs) }
          resume = [regle ? "Corriger : #{ligne_regle(regle)}" : "Nouvelle règle", "Après : #{resultat[:regle]}", resultat[:bilan]]
          resume << resultat[:exemples] if resultat[:exemples].present?
          Plan.new(resume: resume.join("\n"), empreinte: [regle && etat_de(regle), signature(attributs)],
                   donnees: { id: regle&.id, attributs: attributs })
        end

        def appliquer(plan)
          resultat = appliquer_regle(plan.donnees[:id], plan.donnees[:attributs])
          "Règle enregistrée : #{resultat[:regle]}\n#{resultat[:bilan]}"
        end

        def appliquer_regle(id, attributs)
          regle = id ? AllocationRule.find(id) : AllocationRule.new(confidence: 80, position: (AllocationRule.maximum(:position) || 0) + 1)
          regle.assign_attributes(attributs)
          regle.legal_entity_id ||= regle.cash_account&.legal_entity_id ||
                                    LegalEntity.actives.find_by(form: "foundation")&.id
          resultat = metier! { ::Finance::ApplyAllocationRule.new(rule: regle, whodunnit: whodunnit).run! }

          { regle: ligne_regle(AllocationRule.includes(:general_account, :team, :legal_entity, :cash_account, :analytic_account, :event).find(regle.id)),
            bilan: bilan(resultat), exemples: exemples(regle) }
        end

        def bilan(resultat)
          morceaux = ["#{resultat.proposed} ligne(s) « À affecter » recevront sa suggestion (#{euros(resultat.proposed_cents)})."]
          morceaux << "#{resultat.replaced_jev} proposition(s) de Jev en attente remplacée(s)." if resultat.replaced_jev.positive?
          morceaux << "#{resultat.others} ligne(s) reconnue(s) gardent la proposition d'une règle placée avant." if resultat.others.positive?
          morceaux << "#{resultat.refused} ligne(s) où cette règle a déjà été refusée ne la reverront pas." if resultat.refused.positive?
          morceaux.join(" ")
        end

        def exemples(regle)
          suggestions = AllocationSuggestion.pending.where(allocation_rule_id: regle.id)
                                            .includes(cash_entry: :cash_account).order(:id).limit(EXEMPLES).to_a
          return nil if suggestions.empty?

          "Par exemple :\n#{suggestions.map { |s| "  #{ligne_tresorerie(s.cash_entry)}" }.join("\n")}"
        end

        def attributs!(arguments, regle)
          a = {}
          a[:label] = arguments["libelle"].to_s.strip if arguments["libelle"].present?
          raise Error, "Donne le libellé de la règle." if regle.nil? && a[:label].blank?

          a[:general_account_id] = compte_general!(arguments["compte"]).id if arguments["compte"].present?
          raise Error, "Donne le compte proposé." if regle.nil? && a[:general_account_id].nil?

          a[:team_id] = pole!(arguments["pole"]).id if arguments["pole"].present?
          a[:legal_entity_id] = entite!(arguments["entite"]).id if arguments["entite"].present?
          a[:analytic_account_id] = analytique!(arguments["analytique"]).id if arguments["analytique"].present?
          if arguments["evenement"].present?
            a[:event_id] = Event.find_by(id: id!(arguments["evenement"], "événement"))&.id ||
                           raise(Error, "Aucun événement ##{arguments['evenement'].to_s.delete('#')}.")
          end
          a[:cash_account_id] = compte_tresorerie!(arguments["compte_tresorerie"]).id if arguments["compte_tresorerie"].present?

          { "iban" => :counterparty_iban, "tiers_contient" => :counterparty_name_contains,
            "communication_contient" => :communication_contains, "code_transaction" => :transaction_code }.each do |cle, champ|
            a[champ] = arguments[cle].to_s.strip.presence if arguments.key?(cle)
          end
          if arguments.key?("sens")
            a[:direction] = arguments["sens"].blank? ? nil : SENS[arguments["sens"]] || raise(Error, "sens : entree ou sortie.")
          end
          { "min" => :min_amount_cents, "max" => :max_amount_cents }.each do |cle, champ|
            a[champ] = arguments[cle].blank? ? nil : cents!(arguments[cle], cle).abs if arguments.key?(cle)
          end
          a[:confidence] = entier!(arguments["confiance"], "confiance") if arguments["confiance"].present?
          a[:position] = entier!(arguments["ordre"], "ordre") if arguments["ordre"].present?
          a[:active] = arguments["active"] if [true, false].include?(arguments["active"])
          a
        end

        def entier!(valeur, champ)
          Integer(valeur.to_s, exception: false) || raise(Error, "#{champ} : un nombre entier.")
        end
      end
    end
  end
end
