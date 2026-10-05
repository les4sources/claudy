module Mcp
  module Tools
    module Sejours
      class Disponibilites < Base
        include Commun

        tool "disponibilites",
             title: "Disponibilités",
             description: "Ce qui est libre sur une période : les gîtes (et leurs chambres libres quand le gîte est " \
                          "pris en partie), les espaces jour par jour, et les créneaux d'activités avec leurs " \
                          "places restantes (identifiants à passer à creer_sejour ou modifier_sejour).",
             schema: {
               properties: {
                 du: DATE.merge(description: "Arrivée (AAAA-MM-JJ)."),
                 au: DATE.merge(description: "Départ (AAAA-MM-JJ). La nuit du départ n'est pas comptée.")
               },
               required: %w[du au]
             }

        MAX_JOURS = 62

        def call(arguments)
          du = date!(arguments["du"], "du")
          au = date!(arguments["au"], "au")
          raise Error, "« au » doit suivre « du »." if au < du
          raise Error, "Période trop longue (#{MAX_JOURS} jours au plus)." if (au - du).to_i > MAX_JOURS

          [gites(du, au), espaces(du, au), creneaux(du, au)].join("\n\n")
        end

        private

        def gites(du, au)
          noms = Pricing::Catalog::LODGING_RATES.keys
          lignes = Lodging.where(name: noms).sort_by { |l| noms.index(l.name) || 99 }.map do |gite|
            next "- #{gite.name} (##{gite.id}) : libre" if gite.available_between?(du, [au, du + 1].max)

            occupants = Booking.where(lodging_id: gite.id, status: Stay::BLOCKING_STATUSES)
                               .where("from_date < ? AND to_date > ?", [au, du + 1].max, du).to_a
            sejours = StayItem.where(bookable_type: "Booking", bookable_id: occupants.map(&:id)).pluck(:stay_id).uniq
            chambres = gite.rooms.select { |r| gite.rooms_available_between?([r.id], du, [au, du + 1].max) }.map(&:name)
            "- #{gite.name} (##{gite.id}) : PRIS#{" (séjours #{sejours.map { |id| "##{id}" }.join(', ')})" if sejours.any?}" \
              "#{" — chambres libres : #{chambres.join(', ')}" if chambres.any?}"
          end
          "Gîtes du #{du} au #{au} :\n#{lignes.join("\n")}"
        end

        def espaces(du, au)
          jours = (du..au).to_a
          lignes = Space.all.map do |espace|
            pris = jours.reject { |jour| espace.available_on?(jour) }
            "- #{espace.name} : #{pris.empty? ? 'libre tous les jours' : "pris le #{pris.map { |j| j.strftime('%d/%m') }.join(', ')}"}"
          end
          "Espaces :\n#{lignes.join("\n")}"
        end

        def creneaux(du, au)
          liste = ExperienceAvailability.assignable_between(user, du, au).to_a
          return "Aucun créneau d'activité sur la période." if liste.empty?

          lignes = liste.map do |creneau|
            places = creneau.available_spots
            "- Créneau ##{creneau.id} #{creneau.experience&.name} le #{creneau.available_on} à #{creneau.starts_at} : " \
              "#{if places.nil? then 'sans limite' elsif places.zero? then 'complet' else "#{places} place(s)" end}"
          end
          "Créneaux d'activités :\n#{lignes.join("\n")}"
        end
      end
    end
  end
end
