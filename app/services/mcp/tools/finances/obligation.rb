module Mcp
  module Tools
    module Finances
      # Comptabilité > Échéancier > Obligations (ComplianceObligationsController
      # #create et #update) : une obligation et le calendrier de ses échéances,
      # régénéré sur douze mois à chaque enregistrement. Pas de suppression :
      # une obligation se désactive.
      class Obligation < Ecriture
        include Commun

        FREQUENCES = { "une_fois" => "once", "mensuelle" => "monthly", "trimestrielle" => "quarterly", "annuelle" => "yearly" }.freeze
        COUVRE = { "precedente" => "previous", "en_cours" => "current" }.freeze

        tool "obligation",
             title: "Créer ou corriger une obligation de l'échéancier",
             description: "Une obligation légale ou fiscale d'une entité (déclaration TVA, comptes annuels, " \
                          "assurance…) : titre, entité, fréquence, première échéance, fin, période couverte (la " \
                          "précédente, ex. TVA d'avril pour T1 ; ou celle en cours), paiement ou non, responsable " \
                          "(email d'un compte Claudy), consignes, active. Les échéances des douze prochains mois sont " \
                          "créées ou retirées en conséquence. Les obligations : echeancier `obligations`.",
             schema: {
               properties: {
                 obligation: { type: %w[integer string], description: "Pour corriger : l'obligation (#id ou titre). Absente : nouvelle obligation." },
                 titre: { type: "string" },
                 entite: ENTITE,
                 frequence: { type: "string", enum: FREQUENCES.keys, description: "Défaut à la création : annuelle." },
                 premiere_echeance: DATE,
                 fin: DATE.merge(description: "Chaîne vide pour l'effacer."),
                 couvre: { type: "string", enum: COUVRE.keys, description: "Défaut à la création : precedente." },
                 paiement: { type: "boolean", description: "L'échéance se solde par une facture à payer." },
                 responsable: { type: "string", description: "Email du compte Claudy responsable, « moi », ou « aucun »." },
                 consignes: { type: "string" },
                 active: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          obligation = arguments["obligation"].present? ? obligation!(arguments["obligation"]) : nil
          attributs = attributs!(arguments, obligation)
          raise Error, "Rien à changer." if obligation && attributs.empty?

          apres = simuler { ecrire(obligation&.id, attributs) }
          resume = obligation ? "Corriger : #{ligne_obligation(obligation)}\nAprès : #{apres}" : "Nouvelle obligation : #{apres}"
          Plan.new(resume: resume, empreinte: [obligation && etat_de(obligation), attributs.transform_values(&:to_s).sort],
                   donnees: { id: obligation&.id, attributs: attributs })
        end

        def appliquer(plan)
          "Obligation enregistrée : #{ecrire(plan.donnees[:id], plan.donnees[:attributs])}"
        end

        def ecrire(id, attributs)
          obligation = id ? ComplianceObligation.find(id) : ComplianceObligation.new
          metier! { obligation.update!(attributs) }
          rapport = ::ComplianceDeadlines::Generate.new(obligations: ComplianceObligation.where(id: obligation.id)).run!
          "#{ligne_obligation(obligation.reload)} · #{rapport}"
        end

        def obligation!(reference)
          texte = reference.to_s.strip.delete_prefix("#")
          return ComplianceObligation.find_by(id: texte) || raise(Error, "Aucune obligation ##{texte}.") if texte.match?(/\A\d+\z/)

          trouvees = ComplianceObligation.where("title ILIKE ?", "%#{ComplianceObligation.sanitize_sql_like(texte)}%").includes(:legal_entity).to_a
          return trouvees.first if trouvees.one?
          raise Error, "Aucune obligation ne correspond à « #{texte} »." if trouvees.empty?

          raise Error, "Plusieurs obligations correspondent : #{trouvees.map { |o| "##{o.id} #{o.title} (#{o.legal_entity.name})" }.join(', ')}."
        end

        def ligne_obligation(o)
          "##{o.id} #{o.title} · #{o.legal_entity&.name} · #{o.frequency_label.downcase} dès le #{o.first_due_on}" \
            "#{" jusqu'au #{o.ends_on}" if o.ends_on}#{' · paiement' if o.payment}#{" · #{o.responsible_user.email}" if o.responsible_user}" \
            "#{' · INACTIVE' unless o.active?}"
        end

        def attributs!(arguments, obligation)
          a = {}
          a[:title] = arguments["titre"].to_s.strip if arguments["titre"].present?
          a[:legal_entity_id] = entite_meme_inactive!(arguments["entite"]).id if arguments["entite"].present?
          if arguments["frequence"].present?
            a[:frequency] = FREQUENCES[arguments["frequence"]] || raise(Error, "frequence : #{FREQUENCES.keys.join(', ')}.")
          end
          a[:first_due_on] = date!(arguments["premiere_echeance"], "premiere_echeance") if arguments["premiere_echeance"].present?
          a[:ends_on] = date_ou_nil(arguments["fin"], "fin") if arguments.key?("fin")
          a[:covers] = COUVRE[arguments["couvre"]] || raise(Error, "couvre : #{COUVRE.keys.join(', ')}.") if arguments["couvre"].present?
          a[:payment] = arguments["paiement"] unless arguments["paiement"].nil?
          a[:responsible_user_id] = responsable!(arguments["responsable"]) if arguments["responsable"].present?
          a[:instructions] = arguments["consignes"].to_s.strip.presence if arguments.key?("consignes")
          a[:active] = arguments["active"] unless arguments["active"].nil?
          return a if obligation

          manquants = { title: "titre", legal_entity_id: "entite", first_due_on: "premiere_echeance" }.reject { |champ, _| a[champ].present? }
          raise Error, "Pour créer une obligation, donne : #{manquants.values.join(', ')}." if manquants.any?

          { frequency: "yearly", covers: "previous", active: true, responsible_user_id: user.id }.merge(a)
        end

        def responsable!(valeur)
          texte = valeur.to_s.strip
          return nil if texte.casecmp?("aucun")
          return user.id if texte.casecmp?("moi")

          User.find_by("LOWER(email) = ?", texte.downcase)&.id || raise(Error, "Aucun compte Claudy avec l'email « #{texte} ».")
        end
      end
    end
  end
end
