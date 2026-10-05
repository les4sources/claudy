module Mcp
  module Tools
    module Cuisine
      # Une ligne de la page Cuisine dépliée : précisions, validation, prix,
      # liste de courses (Kitchen::OrdersController#shopping_list) et historique.
      class FichePrestation < Base
        include Commun

        tool "fiche_prestation",
             title: "Fiche d'une prestation de cuisine",
             description: "Le détail d'une prestation de cuisine : pour qui, quand, combien, statut client, réponse " \
                          "de la cuisine, responsable, prix (barème ou imposé, remise trio), précisions (allergies, " \
                          "régimes), avertissements, liste de courses d'un buffet ou d'un apéro, et derniers changements.",
             schema: { properties: { prestation: PRESTATION }, required: %w[prestation] }

        def call(arguments)
          order = prestation!(arguments["prestation"])
          [entete(order), courses(order), historique(order)].compact.join("\n\n")
        end

        private

        def entete(order)
          lignes = [ligne_prestation(order)]
          lignes << "Famille : #{order.family_label} · origine : #{order.origin_label}"
          lignes << "Noté au premier contact : « #{order.contact_label} »" if order.contact_label.present?
          lignes << "Réponse de la cuisine le #{I18n.l(order.validated_at, format: '%d/%m/%Y %H:%M')}" if order.validated_at
          lignes << "Prix : #{euros(order.unit_price_effective_cents)} par personne " \
                    "#{order.unit_price_cents ? '(prix imposé)' : '(barème)'} → #{euros(order.price_cents)}" \
                    "#{' · remise formule trio' if order.trio_discounted?}"
          lignes << "Coût saisi : #{euros(order.cost_cents)} · marge #{euros(order.margin_cents)}" if order.cost_cents
          lignes << "Précisions : #{order.notes}" if order.notes.present?
          lignes << "Email de la cuisine : #{destinataire_cuisine(order) || 'aucun (pas de responsable)'}"
          lignes.concat(avertissements(order))
          lignes.join("\n")
        end

        def courses(order)
          return nil unless %w[buffet apero].include?(order.family)

          liste = Kitchen::ShoppingList.new(order)
          return "Liste de courses : aucun produit paramétré pour ce type (reglages_cuisine)." if liste.empty?

          "Liste de courses (#{order.people} pers.) :\n" \
            "#{liste.lines.map { |l| "- #{l.product.name} : #{l.display}#{" (#{l.product.note})" if l.product.note.present?}" }.join("\n")}"
        end

        def historique(order)
          versions = order.versions.reorder(created_at: :desc).limit(6).to_a
          return nil if versions.empty?

          lignes = versions.map do |version|
            champs = version.changeset.keys - %w[updated_at created_at id]
            "- #{I18n.l(version.created_at, format: '%d/%m/%Y %H:%M')} #{version.event} par #{version.whodunnit.presence || '?'}" \
              "#{" : #{champs.join(', ')}" if champs.any?}"
          end
          "Derniers changements :\n#{lignes.join("\n")}"
        end
      end
    end
  end
end
