module Mcp
  module Tools
    module Finances
      # Comptabilité > Fournisseurs > Tiers (ThirdPartiesController#index) :
      # fournisseurs et clients de la comptabilité.
      class Tiers < Base
        include Commun

        TYPES = { "fournisseur" => "supplier", "client" => "customer", "les_deux" => "both" }.freeze
        LIMITE = 80

        tool "tiers",
             title: "Tiers de la comptabilité",
             description: "Les fournisseurs et clients (#id, code, type, TVA, IBAN masqué, email, membre ou client " \
                          "rattaché), filtrables par recherche (nom ou code) et par type ; actifs seulement, sauf " \
                          "`inactifs`. Créer, corriger, désactiver : enregistrer_tiers.",
             schema: {
               properties: {
                 recherche: { type: "string", description: "Nom ou code." },
                 type: { type: "string", enum: TYPES.keys },
                 inactifs: { type: "boolean", description: "Inclure les tiers désactivés." }
               }
             }

        def call(arguments)
          scope = ThirdParty.ordered.includes(:human, :customer)
          scope = scope.search(arguments["recherche"]) if arguments["recherche"].present?
          if arguments["type"].present?
            scope = scope.where(kind: TYPES[arguments["type"]] || raise(Base::Error, "type : #{TYPES.keys.join(', ')}."))
          end
          scope = scope.actives unless arguments["inactifs"]
          tiers = scope.limit(LIMITE + 1).to_a
          return "Aucun tiers." if tiers.empty?

          lignes = tiers.first(LIMITE).map { |t| ligne_tiers(t) }
          lignes << "… et d'autres : précise la recherche." if tiers.size > LIMITE
          lignes.join("\n")
        end

        private

        def ligne_tiers(t)
          ["##{t.id} #{t.name} (#{t.code}, #{t.kind_label.downcase})",
           ("TVA #{t.vat_number}" if t.vat_number.present?),
           ("IBAN #{t.iban_masked}" if t.iban.present?),
           t.email.presence,
           ("membre #{t.human.name}" if t.human),
           ("client #{t.customer.try(:decorate)&.try(:display_name) || "##{t.customer_id}"}" if t.customer),
           ("DÉSACTIVÉ" unless t.active)].compact.join(" · ")
        end
      end
    end
  end
end
