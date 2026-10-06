module Mcp
  module Tools
    module Carte
      # Ce que partagent les outils de la carte du domaine et des plantes :
      # plantes nourricières, catalogue d'espèces, calendrier de récolte,
      # carnet de tâches, notes, objets de la carte, fils de commentaires,
      # relevés de biodiversité.
      #
      # La carte est fermée aux porteurs d'activité restreints
      # (`BaseController::RESTRICTED_ALLOWLIST`) : ces outils aussi.
      #
      # Ce qui se dessine à la main (zones, tracés de réseau, aménagements,
      # croquis) et ce qui demande une photo (Pl@ntNet, bio-indicatrices) reste
      # à l'écran.
      module Commun
        PLANTE = {
          type: %w[integer string],
          description: "La plante : #id (identifiant Claudy, rendu par plantes), « n°42 » (son numéro sur le terrain) ou son nom."
        }.freeze
        ESPECE = { type: %w[integer string], description: "L'espèce : #id ou son nom (« Pommier »)." }.freeze
        ELEMENT = { type: %w[integer string], description: "L'objet de la carte : #id, rendu par elements_carte." }.freeze
        LATITUDE = { type: "number", description: "Latitude WGS84 (ex. 50.3349)." }.freeze
        LONGITUDE = { type: "number", description: "Longitude WGS84 (ex. 4.8571)." }.freeze
        MOIS = {
          type: "array", items: { type: %w[integer string] },
          description: "Mois : numéros 1 à 12 ou noms (« mars », « sept. »)."
        }.freeze
        TEXTE = { type: "string", description: "Texte brut." }.freeze

        NOMS_MOIS = (1..12).each_with_object({}) do |mois, noms|
          [I18n.t("date.month_names", locale: :fr)[mois], I18n.t("date.abbr_month_names", locale: :fr)[mois]].each do |nom|
            noms[I18n.transliterate(nom.to_s).downcase.delete(".")] = mois
          end
        end.freeze

        module Garde
          def call(arguments)
            if user.restricted_to_own_activities?
              raise Base::Error, "La carte du domaine n'est pas accessible à un compte de porteur d'activité, comme dans Claudy."
            end

            super
          end
        end

        def self.included(base)
          base.prepend(Garde)
        end

        private

        def id!(reference, quoi)
          id = reference.to_s.delete("#").strip
          raise Base::Error, "Identifiant de #{quoi} illisible : « #{reference} »." unless id.match?(/\A\d+\z/)

          id.to_i
        end

        # #12 ou 12 : l'identifiant ; « n°42 » : le numéro de terrain ; sinon
        # le nom, l'espèce ou la variété, s'il ne désigne qu'une plante.
        def plante!(reference)
          texte = reference.to_s.strip
          raise Base::Error, "Précise la plante (#id, n°42 ou nom)." if texte.empty?

          if texte.match?(/\A#?\d+\z/)
            return Plant.includes(:plant_species, :plant_variety, :map_feature).find_by(id: texte.delete("#")) ||
                   raise(Base::Error, "Aucune plante ##{texte.delete('#')}.")
          end

          if (numero = texte[/\An(?:°|o|um(?:éro)?)\.?\s*(\d+(?:[.,]\d+)?)\z/i, 1])
            return Plant.find_by(number: BigDecimal(numero.tr(",", "."))) || raise(Base::Error, "Aucune plante n°#{numero}.")
          end

          trouvees = Plant.search(texte).includes(:plant_species, :plant_variety).ordered.limit(11).to_a
          exacte = trouvees.select { |p| p.display_name.to_s.casecmp?(texte) }
          trouvees = exacte if exacte.one?
          return trouvees.first if trouvees.one?
          raise Base::Error, "Aucune plante ne correspond à « #{texte} »." if trouvees.empty?

          raise Base::Error, "Plusieurs plantes correspondent à « #{texte} » : " \
                             "#{trouvees.first(10).map { |p| nom_plante(p) }.join(', ')}. Précise l'identifiant."
        end

        def espece!(reference)
          texte = reference.to_s.strip
          raise Base::Error, "Précise l'espèce (#id ou nom)." if texte.empty?
          if texte.match?(/\A#?\d+\z/)
            return PlantSpecies.find_by(id: texte.delete("#")) || raise(Base::Error, "Aucune espèce ##{texte.delete('#')}.")
          end

          exacte = PlantSpecies.named(texte).first
          return exacte if exacte

          trouvees = PlantSpecies.search(texte).ordered.limit(11).to_a
          return trouvees.first if trouvees.one?
          raise Base::Error, "Aucune espèce ne s'appelle « #{texte} » dans le catalogue." if trouvees.empty?

          raise Base::Error, "Plusieurs espèces correspondent à « #{texte} » : #{trouvees.map(&:full_name).join(', ')}."
        end

        def element!(reference)
          MapFeature.includes(:map_layer).find_by(id: id!(reference, "objet")) ||
            raise(Base::Error, "Aucun objet de la carte ##{reference.to_s.delete('#')}.")
        end

        # Un compte Claudy : « moi », une adresse email ou le nom d'un membre.
        def utilisateur!(reference)
          texte = reference.to_s.strip
          return user if texte.empty? || texte.casecmp?("moi")
          return User.find_by("lower(email) = ?", texte.downcase) || raise(Base::Error, "Aucun compte « #{texte} ».") if texte.include?("@")

          humains = Human.where("name ILIKE ?", "%#{Human.sanitize_sql_like(texte)}%").includes(:user).to_a
          humain = humains.find { |h| h.name.casecmp?(texte) } || (humains.first if humains.one?)
          raise Base::Error, "Plusieurs membres correspondent à « #{texte} » : #{humains.map(&:name).join(', ')}." if humain.nil? && humains.many?
          raise Base::Error, "Aucun membre ne s'appelle « #{texte} »." if humain.nil?

          humain.user || raise(Base::Error, "#{humain.name} n'a pas de compte Claudy.")
        end

        def coordonnees!(latitude, longitude)
          lat = Float(latitude.to_s.tr(",", "."), exception: false)
          lng = Float(longitude.to_s.tr(",", "."), exception: false)
          unless lat&.finite? && lng&.finite? && lat.between?(-90, 90) && lng.between?(-180, 180)
            raise Base::Error, "Position illisible : il faut une latitude et une longitude (WGS84)."
          end

          [lat, lng]
        end

        # [9, "oct", "novembre"] → [9, 10, 11]
        def mois!(valeurs, champ = "mois")
          Array(valeurs).map do |valeur|
            texte = I18n.transliterate(valeur.to_s.strip).downcase.delete(".")
            numero = Integer(texte, exception: false) || NOMS_MOIS[texte]
            raise Base::Error, "#{champ} : mois illisible « #{valeur} » (1 à 12, ou son nom)." unless numero&.between?(1, 12)

            numero
          end.uniq.sort
        end

        # Une clé d'une liste fermée, ou son libellé français.
        def choix!(valeur, choix, champ)
          return nil if valeur.nil? || valeur.to_s.strip.empty?

          texte = valeur.to_s.squish
          return texte if choix.key?(texte)

          cle = choix.find { |_, libelle| I18n.transliterate(libelle.to_s).casecmp?(I18n.transliterate(texte)) }&.first
          cle || raise(Base::Error, "#{champ} « #{texte} » inconnu. Valeurs : #{choix.map { |k, v| "#{k} (#{v})" }.join(', ')}.")
        end

        def nom_plante(plante)
          numero = plante.number_label ? "n°#{plante.number_label} " : ""
          "##{plante.id} #{numero}#{plante.display_name}"
        end

        def position(plante)
          return "à placer" unless plante.placed?

          "placée (#{format('%.6f', plante.latitude)}, #{format('%.6f', plante.longitude)})"
        end

        def ligne_plante(plante)
          details = [nom_plante(plante)]
          espece = plante.species_and_variety_name
          details << espece if espece && espece != plante.display_name
          details << plante.status_label
          details << plante.health_label if plante.health
          details << plante.stratum_label if plante.stratum
          details << "zone #{plante.zone}" if plante.zone
          details << position(plante) unless plante.status == "to_place" && !plante.placed?
          details.join(" · ")
        end

        def ligne_fenetre(fenetre) = "#{fenetre.part_label} : #{fenetre.months_label}"

        def ligne_tache(tache)
          mois = tache.months.any? ? tache.months.map { |m| MapTask.month_abbr(m) }.join(", ") : "sans mois"
          "Tâche ##{tache.id} #{tache.label} · #{tache.sector_label} · #{mois}" \
            "#{" · #{tache.frequency}" if tache.frequency.present?}#{" · #{tache.notes.squish.truncate(80)}" if tache.notes.present?}"
        end

        def ligne_note(note)
          "Note ##{note.id} du #{I18n.l(note.noted_on)}#{" (#{note.author.display_name})" if note.author} : #{note.body.squish.truncate(200)}"
        end

        def point(feature)
          coordonnees = feature.geometry.is_a?(Hash) && feature.geometry["type"] == "Point" ? feature.geometry["coordinates"] : nil
          coordonnees ? "(#{format('%.6f', coordonnees[1])}, #{format('%.6f', coordonnees[0])})" : nil
        end

        def ligne_element(feature)
          forme = case feature.geometry_type
                  when "Point" then "point #{point(feature)}"
                  when "LineString" then "tracé de #{feature.length_in_meters.to_f.round} m"
                  when "Polygon" then "zone"
                  else "sans géométrie"
                  end
          "Objet ##{feature.id} #{feature.display_name.presence || 'sans nom'} · #{feature.feature_kind} · " \
            "#{feature.map_layer&.name} · #{forme}"
        end

        def etat_de(record)
          [record.class.name, record.id, record.updated_at&.utc&.iso8601(6)]
        end

        def signature(arguments)
          trier = lambda do |valeur|
            case valeur
            when Hash then valeur.except("motif", "confirmation").sort.to_h { |cle, v| [cle, trier.call(v)] }
            when Array then valeur.map { |v| trier.call(v) }
            else valeur
            end
          end
          trier.call(arguments)
        end

        # Une validation refusée revient comme un message lisible.
        def valide!(record)
          return record if record.valid?

          raise Base::Error, record.errors.full_messages.to_sentence
        end
      end
    end
  end
end
