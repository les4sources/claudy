module Mcp
  module Tools
    module Collectif
      # Les rassemblements (réunions) du calendrier « organisation », et leurs
      # catégories (GatheringsController#index).
      class Rassemblements < Base
        include Commun

        tool "rassemblements",
             title: "Rassemblements (réunions)",
             description: "Liste les rassemblements du collectif (réunions, cercles, plénières…) : à venir (défaut) ou " \
                          "passés, filtrables par pôle, catégorie et période. Donne aussi les catégories, avec leur " \
                          "horaire par défaut.",
             schema: {
               properties: {
                 quand: { type: "string", enum: %w[a_venir passes tous], description: "Défaut : a_venir." },
                 pole: { type: "string", description: "Nom ou identifiant du pôle." },
                 categorie: { type: "string", description: "Nom de la catégorie." },
                 du: DATE, au: DATE
               }
             }

        LIMITE = 60

        def call(arguments)
          scope = Gathering.includes(:gathering_category, :teams, :agenda_items)
          scope = scope.where(id: Gathering.for_team(pole!(arguments["pole"]).id).select(:id)) if arguments["pole"].present?
          if arguments["categorie"].present?
            categories = GatheringCategory.where("name ILIKE ?", "%#{GatheringCategory.sanitize_sql_like(arguments['categorie'])}%")
            scope = scope.where(gathering_category_id: categories.select(:id))
          end
          du = date_ou_nil(arguments["du"], "du")
          au = date_ou_nil(arguments["au"], "au")
          scope = scope.where(starts_at: du.beginning_of_day..) if du
          scope = scope.where(starts_at: ..au.end_of_day) if au
          scope = case arguments["quand"].presence || "a_venir"
                  when "a_venir" then scope.where(ends_at: Time.current..).order(:starts_at)
                  when "passes" then scope.where(ends_at: ...Time.current).order(starts_at: :desc)
                  else scope.order(starts_at: :desc)
                  end
          liste = scope.limit(LIMITE).to_a
          lignes = liste.map do |g|
            ouverts = g.agenda_items.count { |point| !point.completed? }
            "#{ligne_rassemblement(g)} · ODJ #{g.agenda_items.size} point(s)#{", #{ouverts} ouvert(s)" if ouverts.positive?}"
          end
          [lignes.presence&.join("\n") || "Aucun rassemblement.", categories].join("\n\n")
        end

        private

        def categories
          lignes = GatheringCategory.order(:name).map do |c|
            horaire = c.default_start_time ? "#{c.default_start_time.strftime('%H:%M')}, #{c.default_duration_minutes || 60} min" : "horaire variable"
            "- #{c.name} (#{horaire})"
          end
          "Catégories :\n#{lignes.join("\n")}"
        end
      end
    end
  end
end
