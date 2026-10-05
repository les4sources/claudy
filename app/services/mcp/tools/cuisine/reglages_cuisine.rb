module Mcp
  module Tools
    module Cuisine
      # Paramètres > Cuisine et les produits de buffet (Kitchen::SettingsController,
      # Kitchen::ProductsController#index).
      class ReglagesCuisine < Base
        include Commun

        tool "reglages_cuisine",
             title: "Réglages de la cuisine",
             description: "Les réglages de la cuisine : familles proposées (repas, buffets, apéros), responsable par " \
                          "défaut, plafond de convives et délai d'usage de chacune, email de coordination (refus), " \
                          "comptes de charge suivis, tarifs par personne, et produits de buffet avec leurs quantités " \
                          "par personne (identifiants compris).",
             schema: { properties: {} }

        def call(_arguments)
          [familles, general, produits].join("\n\n")
        end

        private

        def familles
          lignes = Kitchen::Config.families.map do |famille|
            cle = famille[:key]
            responsable = Kitchen::Config.default_human(cle)&.name || "personne"
            plafond = Kitchen::Config.max_people(cle)
            delai = Kitchen::Config.lead_days(cle)
            "- #{famille[:label]} (#{cle}) : #{Kitchen::Config.enabled?(cle) ? 'proposée' : 'RETIRÉE de l\'offre'} · " \
              "responsable par défaut #{responsable} · plafond #{plafond ? "#{plafond} convives" : 'aucun'} · " \
              "délai #{delai ? "#{delai} jours" : 'aucun'}"
          end
          tarifs = MealOrder::KINDS.map { |kind| "#{kind} #{euros(Pricing::Catalog.meal_per_person_cents(kind))}" }
          "Familles :\n#{lignes.join("\n")}\nTarifs par personne (barème) : #{tarifs.join(' · ')}"
        end

        def general
          comptes = Kitchen::Config.expense_accounts.map { |c| "#{c.code} #{c.name}" }
          "Email de coordination (refus de la cuisine) : #{Kitchen::Config.coordinator_email}\n" \
            "Comptes de charge suivis : #{comptes.join(', ').presence || 'aucun'}"
        end

        def produits
          liste = KitchenProduct.ordered.to_a
          return "Produits de buffet : aucun." if liste.empty?

          lignes = liste.map do |produit|
            doses = produit.kinds.map { |kind| "#{kind} #{produit.quantity_label(kind)}" }.join(", ")
            "- Produit ##{produit.id} #{produit.name}#{' [inactif]' unless produit.active?} : #{doses} par personne" \
              "#{" · #{produit.note}" if produit.note.present?}"
          end
          "Produits de buffet (listes de courses) :\n#{lignes.join("\n")}"
        end
      end
    end
  end
end
