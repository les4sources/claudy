module Mcp
  module Tools
    module Sejours
      # La composition d'un séjour telle que la saisit le formulaire « Séjour »
      # de Claudy, traduite en `Reservations::Draft` — le contrat commun du devis
      # (`PricingModel`), de la création (`Reservations::Builder`) et de
      # l'édition (`Stays::AdminUpdater`). Aucune règle de prix ni de dispo
      # n'est réécrite ici : on ne fait que remplir le même brouillon.
      module Composition
        ESPACES = %w[grande_salle petite_salle cuisine_pro].freeze
        PERIODES = %w[journee soiree journee_et_soiree].freeze

        PROPRIETES = {
          hebergement: { type: "string",
                         description: "Gîte, par son nom (« La Hulotte ») ou son identifiant. Vide (\"\") pour retirer l'hébergement." },
          chambres: { type: "array", items: { type: %w[string integer] },
                      description: "Chambres seules plutôt que le gîte entier : noms ou identifiants des chambres." },
          arrivee: Base::DATE.merge(description: "Date d'arrivée (AAAA-MM-JJ)."),
          depart: Base::DATE.merge(description: "Date de départ (AAAA-MM-JJ). Égale à l'arrivée pour une journée."),
          heure_arrivee: { type: "string", description: "Ex. « 16:00 »." },
          heure_depart: { type: "string", description: "Ex. « 11:00 »." },
          adultes: { type: "integer" },
          enfants: { type: "integer" },
          chiens: { type: "integer", description: "Nombre de chiens (0 par défaut)." },
          nom_groupe: { type: "string" },
          categorie: { type: "string", enum: Stay::CATEGORIES.keys,
                       description: "Catégorie : #{Stay::CATEGORIES.map { |k, v| "#{k} (#{v})" }.join(', ')}." },
          salles: { type: "array", description: "Espaces loués, une ligne par jour.",
                    items: { type: "object", additionalProperties: false, required: %w[espace date periode],
                             properties: { espace: { type: "string", enum: ESPACES }, date: Base::DATE,
                                           periode: { type: "string", enum: PERIODES } } } },
          camping: { type: "integer", description: "Personnes en tente, chaque nuit du séjour (0 pour retirer)." },
          vans: { type: "integer", description: "Vans ou camping-cars, chaque nuit du séjour (0 pour retirer)." },
          terrasse: { type: "array", description: "Terrasse, une ligne par jour.",
                      items: { type: "object", additionalProperties: false, required: %w[date personnes],
                               properties: { date: Base::DATE, personnes: { type: "integer" } } } },
          repas: { type: "array", description: "Repas commandés à la cuisine. Remplace la liste existante.",
                   items: { type: "object", additionalProperties: false, required: %w[type date personnes],
                            properties: { type: { type: "string", enum: MealOrder::KINDS }, date: Base::DATE,
                                          moment: { type: "string", enum: MealOrder::MOMENTS },
                                          personnes: { type: "integer" }, notes: { type: "string" } } } },
          activites: { type: "array", description: "Activités, par créneau (identifiant rendu par disponibilites). " \
                                                   "Remplace la liste existante.",
                       items: { type: "object", additionalProperties: false, required: %w[creneau participants],
                                properties: { creneau: { type: "integer" }, participants: { type: "integer" } } } },
          draps_simples: { type: "integer", description: "Jeux de draps pour lit simple." },
          draps_doubles: { type: "integer", description: "Jeux de draps pour lit double." }
        }.freeze

        private

        # `base` : le brouillon d'un séjour existant (édition). Seuls les champs
        # fournis le modifient ; le reste est conservé tel quel.
        def brouillon(arguments, base: {})
          attrs = base.deep_dup.symbolize_keys
          anciennes_dates = [attrs[:arrival_date], attrs[:departure_date]]

          attrs[:arrival_date] = date!(arguments["arrivee"], "arrivee").iso8601 if arguments.key?("arrivee")
          attrs[:departure_date] = date!(arguments["depart"], "depart").iso8601 if arguments.key?("depart")
          dates_changees = anciennes_dates.map(&:to_s) != [attrs[:arrival_date], attrs[:departure_date]].map(&:to_s)
          nuits = nuits(attrs)

          {
            "heure_arrivee" => :arrival_time, "heure_depart" => :departure_time, "adultes" => :adults,
            "enfants" => :children, "chiens" => :dogs_count, "nom_groupe" => :group_name, "categorie" => :category,
            "draps_simples" => :linen_single, "draps_doubles" => :linen_double
          }.each { |cle, champ| attrs[champ] = arguments[cle] if arguments.key?(cle) }
          attrs[:dogs_count] ||= 0

          hebergement!(attrs, arguments) if arguments.key?("hebergement") || arguments.key?("chambres")
          # La grille nuit par nuit de l'édition n'a de sens que sur les dates
          # d'origine : décalé, le séjour occupe son gîte toutes les nuits.
          attrs[:lodging_night_ids] = [] if dates_changees || arguments.key?("hebergement")
          nuits_par_ressource!(attrs, arguments, nuits, dates_changees)

          attrs[:halls] = salles(arguments["salles"]) if arguments.key?("salles")
          attrs[:space_slots] = {} if arguments.key?("salles")
          attrs[:terrasses] = terrasse(arguments["terrasse"]) if arguments.key?("terrasse")
          attrs[:meals] = repas(arguments["repas"], attrs[:meals]) if arguments.key?("repas")
          attrs[:experiences] = activites(arguments["activites"]) if arguments.key?("activites")

          Reservations::Draft.new(attrs)
        end

        def nuits(attrs)
          return 0 if attrs[:arrival_date].blank? || attrs[:departure_date].blank?

          (Date.parse(attrs[:departure_date].to_s) - Date.parse(attrs[:arrival_date].to_s)).to_i
        end

        def hebergement!(attrs, arguments)
          reference = arguments.key?("hebergement") ? arguments["hebergement"].to_s.strip : attrs[:lodging_id].to_s
          if reference.empty?
            attrs.merge!(lodging_id: nil, booking_type: "lodging", room_ids: [], lodging_night_ids: [])
            return
          end

          gite = gite!(reference)
          attrs[:lodging_id] = gite.id
          chambres = Array(arguments["chambres"]).compact_blank
          if chambres.empty?
            attrs.merge!(booking_type: "lodging", room_ids: [])
          else
            attrs.merge!(booking_type: "rooms", room_ids: chambres.map { |c| chambre!(gite, c).id })
          end
        end

        def gite!(reference)
          return Lodging.find_by(id: reference) || raise(Base::Error, "Aucun gîte #{reference}.") if reference.match?(/\A\d+\z/)

          gites = Lodging.where("name ILIKE ?", "%#{Lodging.sanitize_sql_like(reference)}%").to_a
          exact = gites.find { |g| g.name.casecmp?(reference) }
          return exact if exact
          return gites.first if gites.size == 1

          noms = Lodging.order(:name).pluck(:name).join(", ")
          raise Base::Error, gites.empty? ? "Aucun gîte « #{reference} ». Gîtes : #{noms}." :
                                            "Plusieurs gîtes correspondent à « #{reference} » : #{gites.map(&:name).join(', ')}."
        end

        def chambre!(gite, reference)
          reference = reference.to_s.strip
          chambres = gite.rooms.to_a
          trouvee = chambres.find { |c| c.id.to_s == reference } ||
                    chambres.find { |c| c.name.casecmp?(reference) } ||
                    chambres.select { |c| c.name.downcase.include?(reference.downcase) }.then { |l| l.first if l.one? }
          trouvee || raise(Base::Error, "Chambre « #{reference} » introuvable dans #{gite.name} : " \
                                        "#{chambres.map(&:name).join(', ')}.")
        end

        # Camping et vans se saisissent comme dans le formulaire : un nombre
        # chaque nuit. Une grille d'édition déjà là est gardée si rien ne change.
        def nuits_par_ressource!(attrs, arguments, nuits, dates_changees)
          grille = (attrs[:per_night_resources] || {}).to_h.transform_keys(&:to_s)
          return if grille.empty? && !arguments.key?("camping") && !arguments.key?("vans")

          if dates_changees
            grille = grille.to_h do |cle, valeurs|
              uniques = Array(valeurs).map(&:to_i).uniq
              if uniques.size > 1 && !(cle == "tente" && arguments.key?("camping")) && !(cle == "van" && arguments.key?("vans"))
                raise Base::Error, "Le séjour a un #{cle.tr('_', ' ')} qui varie d'une nuit à l'autre : en changeant les " \
                                   "dates, précise aussi `camping` / `vans`, ou modifie-le dans Claudy."
              end
              [cle, Array.new(nuits, uniques.first.to_i)]
            end
          end
          grille["tente"] = Array.new(nuits, arguments["camping"].to_i) if arguments.key?("camping")
          grille["van"] = Array.new(nuits, arguments["vans"].to_i) if arguments.key?("vans")
          grille.reject! { |_, valeurs| Array(valeurs).all? { |v| v.to_i.zero? } }
          attrs[:per_night_resources] = grille
          attrs[:campings] = []
          attrs[:vans] = []
        end

        def salles(lignes)
          Array(lignes).map do |ligne|
            espace = ligne["espace"].to_s
            periode = ligne["periode"].to_s
            raise Base::Error, "Espace inconnu « #{espace} » (#{ESPACES.join(', ')})." unless ESPACES.include?(espace)
            raise Base::Error, "Période inconnue « #{periode} » (#{PERIODES.join(', ')})." unless PERIODES.include?(periode)

            { kind: espace, date: date!(ligne["date"], "salles.date").iso8601, period: periode }
          end
        end

        def terrasse(lignes)
          Array(lignes).map { |l| { date: date!(l["date"], "terrasse.date").iso8601, people: l["personnes"].to_i } }
                       .select { |l| l[:people].positive? }
        end

        # Les repas déjà commandés gardent leur identifiant quand ils restent
        # identiques (même type, date, moment) : la cuisine garde sa validation.
        def repas(lignes, existants)
          existants = Array(existants).map(&:symbolize_keys)
          Array(lignes).map do |ligne|
            type = ligne["type"].to_s
            raise Base::Error, "Type de repas inconnu « #{type} » (#{MealOrder::KINDS.join(', ')})." unless MealOrder::KINDS.include?(type)

            entree = { kind: type, date: date!(ligne["date"], "repas.date").iso8601, moment: ligne["moment"].presence,
                       people: ligne["personnes"].to_i, notes: ligne["notes"].presence }
            meme = existants.find { |e| e[:kind].to_s == type && e[:date].to_s == entree[:date] && e[:moment].to_s == entree[:moment].to_s }
            entree.merge(id: meme&.dig(:id))
          end
        end

        def activites(lignes)
          permis = ExperienceAvailability.for_user(user)
          Array(lignes).map do |ligne|
            creneau = permis.find_by(id: ligne["creneau"]) ||
                      raise(Base::Error, "Créneau d'activité #{ligne['creneau']} introuvable (voir disponibilites).")
            { id: creneau.experience_id, availability_id: creneau.id, participants: ligne["participants"].to_i }
          end
        end

        # Le devis tel que le panneau « Devis » du formulaire l'affiche.
        def lignes_devis(quote)
          lignes = quote.lines.map { |l| "- #{l.label} : #{euros(l.amount_cents)}" }
          lignes << "Total : #{euros(quote.total_cents)} · acompte suggéré : #{euros(quote.deposit_cents)}"
          lignes.join("\n")
        end
      end
    end
  end
end
