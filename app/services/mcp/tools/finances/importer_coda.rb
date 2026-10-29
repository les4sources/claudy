require "base64"
require "digest"

module Mcp
  module Tools
    module Finances
      # Comptabilité > Banque & caisse > CODA (CodaImportsController#create) :
      # déposer un fichier CODA. Le connecteur ne transporte pas de fichier, mais
      # un CODA est du TEXTE (lignes de 128 caractères) : Claude lit le fichier
      # que l'utilisateur lui confie et en passe le contenu tel quel. Même service
      # que l'écran, donc mêmes contrôles bloquants : un fichier refusé ne laisse
      # rien derrière lui, un mouvement déjà importé n'est pas doublé.
      #
      # L'export Excel de Beobank (#479), lui, est binaire : il voyage en base64
      # (`contenu_base64`) et, comme à l'écran, un classeur (« PK » en tête) part
      # vers `Beobank::Import`, tout le reste vers `Coda::Import`.
      class ImporterCoda < Ecriture
        include Commun

        TAILLE_MAX = 5.megabytes

        tool "importer_coda",
             title: "Déposer un fichier bancaire (CODA ou Excel Beobank)",
             description: "Importe un relevé bancaire dans le journal de trésorerie, comme l'écran CODA. Un CODA " \
                          "(.cod, .txt) : `contenu` = le texte COMPLET du fichier, sans rien retirer ni reformater " \
                          "(lignes de 128 caractères, de l'enregistrement 0 au 9 ; un export qui en réunit plusieurs, un par " \
                          "compte, passe tel quel). L'export Excel de Beobank (.xlsx, " \
                          "« Vos comptes ») : `contenu_base64` = le fichier encodé en base64, octet pour octet. L'aperçu " \
                          "dit combien de lignes seraient créées ou ignorées (déjà présentes), ou pourquoi le fichier " \
                          "serait refusé (solde qui ne retombe pas, relevé manquant, trou après la dernière ligne " \
                          "connue, compte inconnu). Les lignes arrivent « à affecter » : lignes_tresorerie.",
             schema: {
               properties: {
                 contenu: { type: "string", description: "Le texte intégral du fichier CODA." },
                 contenu_base64: { type: "string",
                                   description: "Le fichier encodé en base64 : l'export Excel de Beobank (.xlsx)." },
                 nom_fichier: { type: "string", description: "Le nom du fichier (ex. « belfius-2026-09.cod »)." }
               },
               required: %w[nom_fichier]
             }

        # Le service tient sa propre transaction, et rien n'y part par email.
        def self.transactionnel? = false

        private

        def planifier(arguments)
          contenu = contenu!(arguments)
          raise Error, "Le contenu du fichier est vide." if contenu.b.strip.empty?
          raise Error, "Fichier trop gros pour le connecteur (#{contenu.bytesize / 1024} Ko) : dépose-le à l'écran." if contenu.bytesize > TAILLE_MAX

          nom = arguments["nom_fichier"].to_s.strip.presence || raise(Error, "Donne le nom du fichier.")
          rapport = simuler { importer(contenu, nom, "claude:#{user.email}") }
          raise Error, rapport.to_text if rapport.status == "already_imported"

          resume = "Dépôt de « #{nom} » : #{rapport.to_text}"
          resume += "\nRien de nouveau : aucune ligne ne serait créée." if rapport.entries_created.zero?
          Plan.new(resume: resume, empreinte: [Digest::SHA256.hexdigest(contenu), nom],
                   donnees: { contenu: contenu, nom: nom })
        end

        def appliquer(plan)
          rapport = importer(plan.donnees[:contenu], plan.donnees[:nom], whodunnit)
          raise Error, rapport.to_text if rapport.status == "already_imported"

          "Dépôt ##{rapport.coda_import&.id} : #{rapport.to_text}\nLes nouvelles lignes attendent dans « À affecter » (lignes_tresorerie)."
        end

        def contenu!(arguments)
          texte = arguments["contenu"].to_s
          base64 = arguments["contenu_base64"].to_s.gsub(/\s/, "")
          raise Error, "Donne `contenu` (un CODA) OU `contenu_base64` (un Excel), pas les deux." if texte.present? && base64.present?
          return texte unless base64.present?

          Base64.strict_decode64(base64)
        rescue ArgumentError
          raise Error, "`contenu_base64` n'est pas du base64 valide : réencode le fichier tel quel."
        end

        # Comme CodaImportsController#importer_for.
        def importer(contenu, nom, auteur)
          if excel?(contenu)
            ::Beobank::Import.new(content: contenu, filename: nom, whodunnit: auteur).run!
          else
            ::Coda::Import.new(content: contenu.dup.force_encoding("UTF-8"), filename: nom, whodunnit: auteur).run!
          end
        rescue ::Coda::Import::Rejected, ::Coda::ParseError, ::Beobank::Import::Rejected, ::Beobank::ParseError => e
          raise Error, "Fichier refusé, rien n'a été importé : #{e.message}"
        end

        def excel?(contenu) = contenu.b.start_with?("PK".b)
      end
    end
  end
end
