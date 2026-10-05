module Mcp
  module Tools
    module Cuisine
      # Paramètres > Cuisine > Produits (Kitchen::ProductsController) : ce qui
      # entre dans la liste de courses d'un buffet ou d'un apéro.
      class EnregistrerProduitCuisine < Ecriture
        include Commun

        tool "enregistrer_produit_cuisine",
             title: "Créer, modifier ou supprimer un produit de buffet",
             description: "Un produit de buffet ou d'apéro et sa quantité PAR PERSONNE pour chaque type concerné " \
                          "(buffet_vege, buffet_viande, apero) : c'est ce que lit la liste de courses. Sans `produit`, " \
                          "crée ; avec, modifie ; avec supprimer, supprime pour de bon (motif obligatoire, pas d'historique).",
             schema: {
               properties: {
                 produit: { type: %w[integer string], description: "Identifiant du produit à modifier (#12), rendu par reglages_cuisine." },
                 nom: { type: "string" },
                 unite: { type: "string", enum: KitchenProduct::UNITS, description: "g, ml ou piece." },
                 quantites: {
                   type: "object", additionalProperties: false,
                   properties: KitchenProduct::KINDS.to_h { |kind| [kind, { type: %w[number string], description: "Par personne ; 0 ou vide : ne concerne pas ce type." }] },
                   description: "Quantité par personne par type. Les types absents gardent leur valeur (en modification)."
                 },
                 note: { type: "string" },
                 position: { type: "integer", description: "Ordre dans la liste." },
                 actif: { type: "boolean" },
                 supprimer: { type: "boolean" }
               }
             }

        CHAMPS = { "nom" => :name, "unite" => :unit, "note" => :note, "position" => :position, "actif" => :active }.freeze

        private

        def planifier(arguments)
          produit = if arguments["produit"].present?
                      KitchenProduct.find_by(id: arguments["produit"].to_s.delete("#")) ||
                        raise(Error, "Aucun produit ##{arguments['produit']}.")
                    end
          return plan_suppression(produit) if arguments["supprimer"]

          cible = produit ? KitchenProduct.find(produit.id) : KitchenProduct.new
          attrs = CHAMPS.each_with_object({}) { |(cle, champ), h| h[champ] = arguments[cle] if arguments.key?(cle) }
          if arguments["quantites"].present?
            doses = (cible.quantities || {}).merge(arguments["quantites"].transform_values { |v| v.to_s.strip == "0" ? "" : v.to_s })
            attrs[:quantities] = doses
          end
          raise Error, "Rien à changer." if attrs.empty?

          cible.assign_attributes(attrs)
          raise Error, cible.errors.full_messages.to_sentence unless cible.valid?

          doses = cible.kinds.map { |kind| "#{kind} #{cible.quantity_label(kind)}" }.join(", ")
          resume = "#{produit ? "Modifier le produit ##{produit.id}" : 'Créer le produit'} « #{cible.name} » " \
                   "(#{cible.unit}) : #{doses} par personne#{' [inactif]' unless cible.active?}" \
                   "#{" · #{cible.note}" if cible.note.present?}"
          Plan.new(resume: resume, empreinte: [produit&.id, produit&.updated_at&.to_f, attrs.transform_values(&:to_s).sort],
                   donnees: { id: produit&.id, attrs: attrs })
        end

        def plan_suppression(produit)
          raise Error, "Donne le produit à supprimer." unless produit

          motif!({ "motif" => @motif })
          Plan.new(resume: "SUPPRIMER pour de bon le produit ##{produit.id} « #{produit.name} » (il sort des listes de courses).",
                   empreinte: [produit.id, produit.updated_at.to_f, :supprimer], donnees: { id: produit.id, supprimer: true })
        end

        def appliquer(plan)
          if plan.donnees[:supprimer]
            produit = KitchenProduct.find(plan.donnees[:id])
            produit.destroy!
            return "Produit « #{produit.name} » supprimé."
          end

          produit = plan.donnees[:id] ? KitchenProduct.find(plan.donnees[:id]) : KitchenProduct.new
          produit.update!(plan.donnees[:attrs])
          "Produit ##{produit.id} « #{produit.name} » enregistré."
        end
      end
    end
  end
end
