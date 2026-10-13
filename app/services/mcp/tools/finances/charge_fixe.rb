module Mcp
  module Tools
    module Finances
      # Comptabilité > Fournisseurs > Charges fixes (RecurringExpensesController
      # #create, #update et #destroy). Une prévision ne porte aucune écriture :
      # la supprimer n'efface aucun fait (soft delete, PaperTrail garde la trace).
      class ChargeFixe < Ecriture
        include Commun

        FREQUENCES = { "mensuelle" => "monthly", "trimestrielle" => "quarterly", "annuelle" => "yearly" }.freeze

        tool "charge_fixe",
             title: "Créer, corriger ou supprimer une charge fixe",
             description: "Une charge qui revient (abonnement, assurance, emprunt) pour que la trésorerie la projette : " \
                          "libellé, montant, fréquence, première échéance, fin éventuelle, fournisseur (sans lui, pas de " \
                          "remplacement par la vraie facture), compte de charge, entité, active ou non. `supprimer` la " \
                          "retire. Les charges existantes : charges_fixes.",
             schema: {
               properties: {
                 charge: { type: %w[integer string], description: "Pour corriger ou supprimer : la charge (#id ou libellé). Absente : nouvelle charge." },
                 supprimer: { type: "boolean" },
                 libelle: { type: "string" },
                 montant: MONTANT,
                 frequence: { type: "string", enum: FREQUENCES.keys, description: "Défaut à la création : mensuelle." },
                 premiere_echeance: DATE.merge(description: "Date de la première échéance."),
                 fin: DATE.merge(description: "Fin du contrat : plus d’échéance après cette date. Chaîne vide pour l’effacer."),
                 fournisseur: { type: "string", description: "Le tiers (nom), ou « aucun »." },
                 compte: COMPTE_GENERAL.merge(description: "Compte de charge (code ou nom), ou « aucun »."),
                 entite: ENTITE.merge(description: "Défaut à la création : la fondation."),
                 active: { type: "boolean" },
                 notes: { type: "string" }
               }
             }

        private

        def planifier(arguments)
          charge = arguments["charge"].present? ? par_nom_ou_libelle!(arguments["charge"]) : nil
          if arguments["supprimer"]
            raise Error, "Donne la charge à supprimer." if charge.nil?

            return Plan.new(resume: "Supprimer : #{ligne(charge)}\nElle sort de la projection de trésorerie.",
                            empreinte: [etat_de(charge), "supprimer"], donnees: { id: charge.id, supprimer: true })
          end

          attributs = attributs!(arguments, charge)
          raise Error, "Rien à changer." if charge && attributs.empty?

          apres = simuler { ecrire(charge&.id, attributs) }
          resume = charge ? "Corriger : #{ligne(charge)}\nAprès : #{apres}" : "Nouvelle charge fixe : #{apres}"
          Plan.new(resume: resume, empreinte: [charge && etat_de(charge), attributs.transform_values(&:to_s).sort],
                   donnees: { id: charge&.id, attributs: attributs })
        end

        def appliquer(plan)
          if plan.donnees[:supprimer]
            charge = RecurringExpense.find(plan.donnees[:id])
            charge.soft_delete!(validate: false)
            return "Charge « #{charge.label} » supprimée."
          end

          "Charge enregistrée : #{ecrire(plan.donnees[:id], plan.donnees[:attributs])}"
        end

        def ecrire(id, attributs)
          charge = id ? RecurringExpense.find(id) : RecurringExpense.new(frequency: "monthly")
          metier! { charge.update!(attributs) }
          ligne(charge.reload)
        end

        def ligne(c)
          ["##{c.id} #{c.label} · #{euros(c.amount_cents)} #{c.frequency_label.downcase}",
           "dès le #{c.first_due_on}", ("jusqu'au #{c.ends_on}" if c.ends_on),
           ("fournisseur #{c.third_party.name}" if c.third_party), ("compte #{c.general_account}" if c.general_account),
           c.legal_entity&.name, ("INACTIVE" unless c.active?)].compact.join(" · ")
        end

        def par_nom_ou_libelle!(reference)
          texte = reference.to_s.strip.delete_prefix("#")
          return RecurringExpense.find_by(id: texte) || raise(Error, "Aucune charge fixe ##{texte}.") if texte.match?(/\A\d+\z/)

          trouvees = RecurringExpense.where("label ILIKE ?", "%#{RecurringExpense.sanitize_sql_like(texte)}%").to_a
          return trouvees.first if trouvees.one?
          raise Error, "Aucune charge fixe ne correspond à « #{texte} »." if trouvees.empty?

          raise Error, "Plusieurs charges correspondent à « #{texte} » : #{trouvees.map { |c| "##{c.id} #{c.label}" }.join(', ')}."
        end

        def attributs!(arguments, charge)
          a = {}
          a[:label] = arguments["libelle"].to_s.strip if arguments["libelle"].present?
          a[:amount_cents] = cents!(arguments["montant"], "montant").abs if arguments["montant"].present?
          if arguments["frequence"].present?
            a[:frequency] = FREQUENCES[arguments["frequence"]] || raise(Error, "frequence : #{FREQUENCES.keys.join(', ')}.")
          end
          a[:first_due_on] = date!(arguments["premiere_echeance"], "premiere_echeance") if arguments["premiere_echeance"].present?
          a[:ends_on] = date_ou_nil(arguments["fin"], "fin") if arguments.key?("fin")
          if arguments["fournisseur"].present?
            a[:third_party_id] = arguments["fournisseur"].to_s.strip.casecmp?("aucun") ? nil : tiers!(arguments["fournisseur"]).id
          end
          if arguments["compte"].present?
            a[:general_account_id] = arguments["compte"].to_s.strip.casecmp?("aucun") ? nil : compte_general!(arguments["compte"]).id
          end
          if arguments["entite"].present?
            a[:legal_entity_id] = entite!(arguments["entite"]).id
          elsif charge.nil?
            a[:legal_entity_id] = LegalEntity.actives.find_by(form: "foundation")&.id || raise(Error, "Donne l'entité.")
          end
          a[:active] = arguments["active"] unless arguments["active"].nil?
          a[:notes] = arguments["notes"].to_s.strip.presence if arguments.key?("notes")
          if charge.nil?
            manquants = { label: "libelle", amount_cents: "montant", first_due_on: "premiere_echeance" }.reject { |champ, _| a[champ].present? }
            raise Error, "Pour créer une charge, donne : #{manquants.values.join(', ')}." if manquants.any?
          end
          a
        end
      end
    end
  end
end
