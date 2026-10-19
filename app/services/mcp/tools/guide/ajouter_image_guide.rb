module Mcp
  module Tools
    module Guide
      # Ajouter une image à une page du Guide — à l'écran, on la glisse dans
      # l'éditeur. Elle est téléversée, rattachée à la page et insérée dans son
      # Markdown, ce qui fait une version de la page.
      class AjouterImageGuide < Ecriture
        include Commun

        TAILLE_MAX = 10.megabytes

        tool "ajouter_image_guide",
             title: "Ajouter une image à une page du Guide",
             description: "Téléverse une image (contenu en base64 : PNG, JPEG, GIF ou WebP, 10 Mo au plus) et l'insère " \
                          "dans la page : à la fin, ou juste après la ligne qui contient `apres`. La légende sert de " \
                          "texte alternatif. Devient une version de la page.",
             schema: {
               properties: {
                 page: PAGE,
                 contenu_base64: { type: "string", description: "Le fichier image encodé en base64 (sans préfixe data:)." },
                 nom_fichier: { type: "string", description: "Ex. bac-admin.jpg" },
                 legende: { type: "string", description: "Ce que montre l'image (texte alternatif)." },
                 apres: { type: "string", description: "Un passage exact de la page : l'image va sous sa ligne. Défaut : à la fin." }
               },
               required: %w[page contenu_base64 nom_fichier]
             }

        private

        def planifier(arguments)
          page = page!(arguments["page"])
          donnees = decoder(arguments["contenu_base64"])
          nom = arguments["nom_fichier"].to_s.strip.presence || "image"
          # Le type se lit dans les octets, pas dans le nom : « x.png » ne suffit pas.
          type = Marcel::MimeType.for(StringIO.new(donnees))
          raise Error, "Ce fichier n'est pas une image (#{type})." unless type.to_s.match?(%r{\Aimage/(png|jpeg|gif|webp)\z})

          apres = arguments["apres"].to_s
          if apres.present? && !page.body.include?(apres)
            raise Error, "Le passage « #{apres.truncate(80)} » n'est pas dans la page ##{page.id}."
          end

          legende = arguments["legende"].to_s.strip.presence || File.basename(nom, ".*").tr("-_", "  ")
          resume = "AJOUTER une image à #{ligne_page(page)}\n" \
                   "Fichier : #{nom} (#{type}, #{ActiveSupport::NumberHelper.number_to_human_size(donnees.bytesize, locale: :fr)})\n" \
                   "Légende : « #{legende} »\nPlace : #{apres.present? ? "sous la ligne « #{apres.truncate(80)} »" : 'à la fin de la page'}"
          Plan.new(resume: resume,
                   empreinte: [page.id, Digest::SHA256.hexdigest(page.body), Digest::SHA256.hexdigest(donnees), nom, legende, apres],
                   donnees: { page: page.id, fichier: donnees, nom: nom, type: type, legende: legende, apres: apres })
        end

        def appliquer(plan)
          d = plan.donnees
          page = GuidePage.find(d[:page])
          blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(d[:fichier]), filename: d[:nom], content_type: d[:type])
          chemin = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
          image = "![#{d[:legende].tr('[]', '()')}](#{chemin})"
          ::Guide::SavePage.new(page, user: user, source: "mcp")
                           .call(body: inserer(page.body, image, d[:apres]), summary: @motif.presence || "Image « #{d[:nom]} » ajoutée")
          "Image ajoutée à #{ligne_page(page.reload)}.\nMarkdown inséré : #{image}\nAdresse : #{lien_page(page)}"
        end

        def decoder(base64)
          texte = base64.to_s.sub(/\Adata:[^,]*,/, "").gsub(/\s/, "")
          raise Error, "Donne le contenu de l'image en base64." if texte.empty?

          donnees = Base64.strict_decode64(texte)
          raise Error, "Image trop lourde : 10 Mo au plus." if donnees.bytesize > TAILLE_MAX

          donnees
        rescue ArgumentError
          raise Error, "Le contenu n'est pas du base64 valide."
        end

        def inserer(corps, image, apres)
          return [corps.rstrip, image].compact_blank.join("\n\n") if apres.blank?

          fin_de_ligne = corps.index("\n", corps.index(apres) + apres.length) || corps.length
          suite = corps[fin_de_ligne..].sub(/\A\n+/, "")
          ["#{corps[0...fin_de_ligne]}\n\n#{image}", suite.presence].compact.join("\n\n")
        end
      end
    end
  end
end
