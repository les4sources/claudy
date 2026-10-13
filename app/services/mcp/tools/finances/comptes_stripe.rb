module Mcp
  module Tools
    module Finances
      # Comptabilité > Banque & caisse > Stripe (StripeController#index) : où en
      # est chaque compte Stripe, et où va chaque catégorie de ventes.
      class ComptesStripe < Base
        include Commun

        tool "comptes_stripe",
             title: "Comptes Stripe",
             description: "Chaque compte Stripe : son mode (par versement, ou grand livre), versements et transactions " \
                          "importés, dernier import, lignes en attente ; en mode grand livre, les correspondances " \
                          "catégorie → compte du plan (#id) et les catégories rencontrées qu'aucune correspondance ne " \
                          "couvre (leurs recettes restent « à affecter »). Changer : mode_stripe, correspondance_stripe.",
             schema: { properties: {} }

        def call(_arguments)
          blocs = ::Finance::StripeAccounts.new.blocks
          return "Aucun compte de trésorerie Stripe." if blocs.empty?

          blocs.map { |bloc| bloc_lisible(bloc) }.join("\n\n")
        end

        private

        def bloc_lisible(bloc)
          compte = bloc[:account]
          lignes = ["#{compte.name} · #{compte.stripe_mode_label}#{" · clé #{compte.stripe_account_key}" if compte.stripe_account_key.present?}" \
                    "#{" · #{compte.legal_entity.name}" if compte.legal_entity}",
                    "  #{bloc[:payouts_count]} versement(s), #{bloc[:transactions_count]} transaction(s), " \
                    "dernier import #{bloc[:last_import_at]&.to_date || '—'}, #{bloc[:pending_count]} ligne(s) en attente"]
          return lignes.join("\n") unless compte.ledger?

          lignes << (bloc[:mappings].empty? ? "  Aucune correspondance : toutes les recettes restent à affecter." : "  Correspondances :")
          bloc[:mappings].each do |m|
            lignes << "    ##{m.id} #{m.category_label} → #{m.general_account}#{" · pôle #{m.team.name}" if m.team}" \
                      "#{" · #{m.legal_entity.name}" if m.legal_entity}#{" · #{m.notes.squish.truncate(60)}" if m.notes.present?}"
          end
          if bloc[:uncovered].any?
            lignes << "  Catégories sans correspondance :"
            bloc[:uncovered].each { |c| lignes << "    #{c[:label]} : #{c[:count]} transaction(s), #{euros(c[:gross_cents])} brut" }
          end
          lignes.join("\n")
        end
      end
    end
  end
end
