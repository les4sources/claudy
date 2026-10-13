module Mcp
  module Tools
    module Finances
      # Comptabilité > Plan comptable (GeneralAccountsController #create,
      # #update et #destroy). Un compte qui porte des écritures ne se supprime
      # pas : il se désactive.
      class CompteGeneral < Ecriture
        include Commun

        NATURES = { "actif" => "asset", "passif" => "liability", "capitaux" => "equity", "produit" => "revenue", "charge" => "expense" }.freeze

        tool "compte_general",
             title: "Créer, corriger ou supprimer un compte du plan comptable",
             description: "Un compte du plan : code (3 à 8 chiffres ; la classe et la nature s'en déduisent à la " \
                          "création), nom, nature, lettrable, actif. `supprimer` le retire s'il ne porte aucune " \
                          "écriture ; sinon, désactive-le (`actif: false`). Le plan : parametrage_compta comptes.",
             schema: {
               properties: {
                 compte: { type: "string", description: "Pour corriger ou supprimer : le code exact du compte. Absent : nouveau compte." },
                 supprimer: { type: "boolean" },
                 code: { type: "string" },
                 nom: { type: "string" },
                 nature: { type: "string", enum: NATURES.keys },
                 lettrable: { type: "boolean", description: "Ses lignes se rapprochent une à une (fournisseurs, clients…)." },
                 actif: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          compte = arguments["compte"].present? ? compte_par_code!(arguments["compte"]) : nil
          if arguments["supprimer"]
            raise Error, "Donne le compte à supprimer." if compte.nil?
            if compte.journal_lines.exists? || compte.cash_accounts.exists?
              raise Error, "#{compte} porte des écritures ou un compte de trésorerie : désactive-le (actif: false) plutôt que de le supprimer."
            end

            return Plan.new(resume: "Supprimer le compte #{compte}.", empreinte: [etat_de(compte), "supprimer"],
                            donnees: { id: compte.id, supprimer: true })
          end

          attributs = attributs!(arguments, compte)
          raise Error, "Rien à changer." if compte && attributs.empty?

          apres = simuler { ecrire(compte&.id, attributs) }
          resume = compte ? "Corriger : #{ligne_compte(compte)}\nAprès : #{apres}" : "Nouveau compte : #{apres}"
          Plan.new(resume: resume, empreinte: [compte && etat_de(compte), attributs.transform_values(&:to_s).sort],
                   donnees: { id: compte&.id, attributs: attributs })
        end

        def appliquer(plan)
          if plan.donnees[:supprimer]
            compte = GeneralAccount.find(plan.donnees[:id])
            raise Error, "Ce compte porte des écritures : désactive-le plutôt." unless compte.destroy

            return "Compte #{compte} supprimé."
          end

          "Compte enregistré : #{ecrire(plan.donnees[:id], plan.donnees[:attributs])}"
        end

        def ecrire(id, attributs)
          compte = id ? GeneralAccount.find(id) : GeneralAccount.new
          metier! { compte.update!(attributs) }
          ligne_compte(compte.reload)
        end

        def ligne_compte(c)
          "#{c} · classe #{c.klass} · #{c.nature_label.downcase}#{' · lettrable' if c.reconcilable}#{' · DÉSACTIVÉ' unless c.active}"
        end

        def compte_par_code!(reference)
          GeneralAccount.find_by(code: reference.to_s.strip.delete_prefix("#")) ||
            raise(Error, "Aucun compte de code « #{reference} » (parametrage_compta comptes).")
        end

        def attributs!(arguments, compte)
          a = {}
          if arguments["code"].present?
            a[:code] = arguments["code"].to_s.strip
            a[:klass] = GeneralAccount.klass_from(a[:code]) if compte.nil?
          end
          a[:name] = arguments["nom"].to_s.strip if arguments["nom"].present?
          a[:nature] = NATURES[arguments["nature"]] || raise(Error, "nature : #{NATURES.keys.join(', ')}.") if arguments["nature"].present?
          a[:nature] ||= GeneralAccount.nature_from(a[:code]) if compte.nil? && a[:code]
          a[:reconcilable] = arguments["lettrable"] unless arguments["lettrable"].nil?
          a[:active] = arguments["actif"] unless arguments["actif"].nil?
          raise Error, "Pour créer un compte, donne : code, nom." if compte.nil? && (a[:code].blank? || a[:name].blank?)

          a
        end
      end
    end
  end
end
